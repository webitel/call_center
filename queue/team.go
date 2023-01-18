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

func (at agentTeam) InviteChatTimeout() uint16 {
	return at.data.InviteChatTimeout
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
		if updatedAt == 0 || team.data.UpdatedAt == updatedAt {
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
	if attempt.queue != nil {
		attempt.queue.StartProcessingForm(attempt) //TODO
	}

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

	if attempt.queue != nil {
		attempt.queue.StartProcessingForm(attempt) //TODO
	}

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

func (tm *agentTeam) SetWrap(queue QueueObject, attempt *Attempt, agent agent_manager.AgentObject, result string) {
	var vars map[string]string = nil

	t := int(tm.WrapUpTime())
	if agent.IsOnDemand() {
		t = 0
	}

	if queue.Endless() && result != AttemptResultTransfer {
		result = AttemptResultEndless
	}

	if res, ok := attempt.AfterDistributeSchema(); ok {
		result = res.Status
		vars = res.Variables
	}

	if res, err := tm.teamManager.store.Member().SetAttemptResult(attempt.Id(), result,
		model.ChannelStateWrapTime, t, vars, attempt.maxAttempts, attempt.waitBetween, attempt.perNumbers); err == nil {
		if res.MemberStopCause != nil {
			attempt.SetMemberStopCause(res.MemberStopCause)
		}

		attempt.SetResult(result)

		e := NewWrapTimeEventEvent(attempt.channel, model.NewInt64(attempt.Id()), agent.UserId(), res.Timestamp, res.Timestamp+(int64(tm.WrapUpTime()*1000)))
		err = tm.teamManager.mq.AgentChannelEvent(attempt.channel, attempt.domainId, attempt.QueueId(), agent.UserId(), e)
		if err != nil {
			wlog.Error(err.Error())
		}
	} else {
		wlog.Error(err.Error())
	}
	queue.Leaving(attempt)
}

func (tm *agentTeam) Reporting(queue QueueObject, attempt *Attempt, agent agent_manager.AgentObject, agentSendReporting bool, transfer bool) {
	if queue.Manager().waitChannelClose && attempt != nil && attempt.Callback() != nil {
		if err := queue.Manager().ReportingAttempt(attempt.Id(), *attempt.Callback(), true); err != nil {
			attempt.Log(err.Error())
		}
		return
	}

	attempt.Log(fmt.Sprintf("reporting %v", agentSendReporting))

	if agentSendReporting {
		attempt.SetResult(AttemptResultSuccess)
		return
	}

	if transfer && !queue.ProcessingTransfer() {
		transfer = false
	}

	// todo on demand - wrap_time
	if agent.IsOnDemand() {
		//timeoutSec = 0
	}

	if !queue.Processing() || transfer {
		s := AttemptResultSuccess
		if transfer {
			s = AttemptResultTransfer
		}

		tm.SetWrap(queue, attempt, agent, s)
		return
	}

	timeoutSec := queue.ProcessingSec()

	if attempt.Result() == "" {
		attempt.SetResult(AttemptResultPostProcessing)
	}
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

func (tm *agentTeam) Missed(attempt *Attempt, agent agent_manager.AgentObject) {

	if _, ok := attempt.AfterDistributeSchema(); ok {
		//TODO
	}

	missed, err := tm.teamManager.store.Member().SetAttemptMissed(attempt.Id(), int(tm.NoAnswerDelayTime()),
		attempt.maxAttempts, attempt.waitBetween, attempt.perNumbers)
	if err != nil {
		wlog.Error(err.Error())
		return
	}

	if missed.MemberStopCause != nil {
		attempt.SetMemberStopCause(missed.MemberStopCause)
	}
	//TODO
	attempt.SetResult(model.MemberStateCancel)

	tm.MissedAgent(missed, attempt, agent)
}

func (tm *agentTeam) CancelAgentAttempt(attempt *Attempt, agent agent_manager.AgentObject) {
	// todo missed or waiting ?

	attempt.SetResult(model.MemberStateCancel)

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

func (tm *agentTeam) Transfer(attempt *Attempt, agent agent_manager.AgentObject) {
	timestamp := model.GetMillis()

	// todo is old agent
	e := NewWrapTimeEventEvent(attempt.channel, model.NewInt64(attempt.Id()), agent.UserId(), timestamp, timestamp+(int64(tm.WrapUpTime()*1000)))
	err := tm.teamManager.mq.AgentChannelEvent(attempt.channel, attempt.domainId, attempt.QueueId(), agent.UserId(), e)
	if err != nil {
		wlog.Error(err.Error())
	}

	return
}
