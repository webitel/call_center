package queue

import (
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"sync"
)

const (
	MAX_TEAM_CACHE        = 10000
	MAX_TEAM_EXPIRE_CACHE = 60 * 60 * 24
)

type teamManager struct {
	store store.Store
	cache utils.ObjectCache
	sync.RWMutex
	mq mq.MQ
}

type agentTeam struct {
	data        *model.Team
	teamManager *teamManager
}

func (at *agentTeam) Name() string {
	return at.data.Name
}

func (at *agentTeam) Id() int64 {
	return at.data.Id
}

func (at *agentTeam) CallTimeout() uint16 {
	return at.data.CallTimeout
}

func (at *agentTeam) MaxNoAnswer() uint16 {
	return at.data.MaxNoAnswer
}

func (at *agentTeam) WrapUpTime() uint16 {
	return at.data.WrapUpTime
}

func (at *agentTeam) NoAnswerDelayTime() uint16 {
	return at.data.NoAnswerDelayTime
}

func NewTeamManager(s store.Store, m mq.MQ) *teamManager {
	return &teamManager{
		store: s,
		mq:    m,
		cache: utils.NewLruWithParams(MAX_TEAM_CACHE, "team", MAX_TEAM_EXPIRE_CACHE, ""),
	}
}

func (tm *teamManager) GetTeam(id int, updatedAt int64) (*agentTeam, *model.AppError) {
	tm.Lock() //TODO
	defer tm.Unlock()

	var team *agentTeam
	var err *model.AppError

	if t, ok := tm.cache.Get(id); ok {
		team = t.(*agentTeam)
		if team.data.UpdatedAt == updatedAt {
			return team, nil
		}
	}

	data, err := tm.store.Team().Get(id)
	if err != nil {
		return nil, err
	}
	team = &agentTeam{
		data:        data,
		teamManager: tm,
	}

	tm.cache.AddWithDefaultExpires(id, team)
	wlog.Debug(fmt.Sprintf("team [%d] %v store to cache", team.Id(), team.Name()))
	return team, err
}

//FIXME store
func (tm *agentTeam) Answered(attempt *Attempt, agent agent_manager.AgentObject) {
	timestamp := model.GetMillis()
	attempt.SetState(model.MemberStateActive)
	e := NewAnsweredEvent(attempt, agent.UserId(), timestamp)
	err := tm.teamManager.mq.AgentChannelEvent(attempt.channel, attempt.domainId, attempt.QueueId(), agent.UserId(), e)
	if err != nil {
		wlog.Error(err.Error())
		return
	}
}

func (tm *agentTeam) Bridged(attempt *Attempt, agent agent_manager.AgentObject) {
	timestamp, err := tm.teamManager.store.Member().SetAttemptBridged(attempt.Id())
	if err != nil {
		wlog.Error(err.Error())
		return
	}
	attempt.SetState(model.MemberStateBridged)

	e := NewBridgedEventEvent(attempt, agent.UserId(), timestamp)
	err = tm.teamManager.mq.AgentChannelEvent(attempt.channel, attempt.domainId, attempt.QueueId(), agent.UserId(), e)
	if err != nil {
		wlog.Error(err.Error())
		return
	}
}

func (tm *agentTeam) Reporting(queue QueueObject, attempt *Attempt, agent agent_manager.AgentObject, agentSendReporting bool) {
	if agentSendReporting {
		// FIXME
		attempt.SetResult(AttemptResultSuccess)
		return
	}

	// todo on demand - wrap_time
	if agent.IsOnDemand() {
		//timeoutSec = 0
	}

	if !queue.Processing() {
		// FIXME
		attempt.SetResult(AttemptResultSuccess)
		attempt.SetState(HookLeaving)
		if timestamp, err := tm.teamManager.store.Member().SetAttemptResult(attempt.Id(), "success", 30,
			model.ChannelStateWrapTime, int(tm.WrapUpTime())); err == nil {

			e := NewWrapTimeEventEvent(attempt.channel, model.NewInt64(attempt.Id()), agent.UserId(), timestamp, timestamp+(int64(tm.WrapUpTime()*1000)))
			err = tm.teamManager.mq.AgentChannelEvent(attempt.channel, attempt.domainId, attempt.QueueId(), agent.UserId(), e)
			if err != nil {
				wlog.Error(err.Error())
			}
		} else {
			wlog.Error(err.Error())
		}
		return
	}

	timeoutSec := queue.ProcessingSec()

	attempt.SetResult(AttemptResultPostProcessing)
	timestamp, err := tm.teamManager.store.Member().SetAttemptReporting(attempt.Id(), timeoutSec)
	if err != nil {
		wlog.Error(err.Error())
		return
	}

	attempt.SetState(model.MemberStateProcessing)

	e := NewProcessingEventEvent(attempt, agent.UserId(), timestamp, timeoutSec, queue.ProcessingRenewalSec())
	err = tm.teamManager.mq.AgentChannelEvent(attempt.channel, attempt.domainId, attempt.QueueId(), agent.UserId(), e)
	if err != nil {
		wlog.Error(err.Error())
		return
	}

	wlog.Debug(fmt.Sprintf("attempt [%d] wait callback result for agent \"%s\", timeout=%d", attempt.Id(), agent.Name(), timeoutSec))
}

func (tm *agentTeam) Missed(attempt *Attempt, holdSec int, agent agent_manager.AgentObject) {
	timestamp, err := tm.teamManager.store.Member().SetAttemptMissed(attempt.Id(), holdSec, int(tm.NoAnswerDelayTime()))
	if err != nil {
		wlog.Error(err.Error())
		return
	}

	e := NewMissedEventEvent(attempt, agent.UserId(), timestamp, timestamp+(int64(tm.NoAnswerDelayTime())*1000))
	err = tm.teamManager.mq.AgentChannelEvent(attempt.channel, attempt.domainId, attempt.QueueId(), agent.UserId(), e)
	if err != nil {
		wlog.Error(err.Error())
		return
	}
}

func (tm *agentTeam) CancelAgentAttempt(attempt *Attempt, agent agent_manager.AgentObject) {
	// todo missed or waiting ?

	missed, err := tm.teamManager.store.Member().CancelAgentAttempt(attempt.Id(), int(tm.NoAnswerDelayTime()))
	if err != nil {
		wlog.Error(err.Error())
		return
	}

	tm.MissedAgent(missed, attempt, agent)
}

func (tm *agentTeam) MissedAgent(missed *model.MissedAgent, attempt *Attempt, agent agent_manager.AgentObject) {
	if missed.NoAnswers != nil && *missed.NoAnswers >= tm.MaxNoAnswer() {
		tm.SetAgentMaxNoAnswer(agent)
	}

	attempt.SetState(HookMissed)
	e := NewMissedEventEvent(attempt, agent.UserId(), missed.Timestamp, missed.Timestamp+(int64(tm.NoAnswerDelayTime())*1000))
	err := tm.teamManager.mq.AgentChannelEvent(attempt.channel, attempt.domainId, attempt.QueueId(), agent.UserId(), e)
	if err != nil {
		wlog.Error(err.Error())
		return
	}
}

func (tm *agentTeam) MissedAgentAndWaitingAttempt(attempt *Attempt, agent agent_manager.AgentObject) {
	missed, err := tm.teamManager.store.Member().SetAttemptMissedAgent(attempt.Id(), int(tm.NoAnswerDelayTime()))
	if err != nil {
		wlog.Error(err.Error())
		return
	}

	tm.MissedAgent(missed, attempt, agent)
	attempt.agent = nil
	attempt.agentChannel = nil
}

func (tm *agentTeam) SetAgentMaxNoAnswer(agent agent_manager.AgentObject) {
	if err := agent.SetBreakOut(); err != nil {
		wlog.Error(fmt.Sprintf("agent \"%s\" change to [break_out] error %s", agent.Name(), err.Error()))
	} else {
		wlog.Debug(fmt.Sprintf("agent \"%s\" changed status to [break_out], maximum no answers in team \"%s\"", agent.Name(), tm.Name()))
	}
}
