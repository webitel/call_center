package queue

import (
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
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
}

type agentTeam struct {
	data *model.Team
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

func (at *agentTeam) RejectDelayTime() uint16 {
	return at.data.RejectDelayTime
}

func (at *agentTeam) BusyDelayTime() uint16 {
	return at.data.BusyDelayTime
}

func (at *agentTeam) NoAnswerDelayTime() uint16 {
	return at.data.NoAnswerDelayTime
}

func (at *agentTeam) OfferingCall(queue QueueObject, agent agent_manager.AgentObject, attempt *Attempt) *model.AppError {
	wlog.Debug(fmt.Sprintf("agent %s[%d] has been changed status to \"%s\" for queue %s",
		agent.Name(), agent.Id(), model.AGENT_STATE_OFFERING, queue.Name()))
	return agent.SetStateOffering(queue.Id())
}

func (at *agentTeam) Talking(queue QueueObject, agent agent_manager.AgentObject, attempt *Attempt) *model.AppError {
	wlog.Debug(fmt.Sprintf("agent %s[%d] has been changed status to \"%s\" for queue %s",
		agent.Name(), agent.Id(), model.AGENT_STATE_TALK, queue.Name()))
	return agent.SetStateTalking()
}

func (at *agentTeam) ReportingCall(queue *CallingQueue, agent agent_manager.AgentObject, call call_manager.Call, attempt *Attempt) *model.AppError {
	var noAnswer = false
	var timeout = 0

	if call.Err() != nil {
		switch call.HangupCause() {
		case model.CALL_HANGUP_NO_ANSWER:
			noAnswer = true
			timeout = int(at.NoAnswerDelayTime())
		case model.CALL_HANGUP_REJECTED:
			timeout = int(at.RejectDelayTime())
		default:
			timeout = int(at.BusyDelayTime())
		}

		queue.MissedAgentAttempt(attempt.Id(), agent.Id(), call)

		if noAnswer && at.MaxNoAnswer() > 0 && at.MaxNoAnswer() <= agent.SuccessivelyNoAnswers()+1 {
			return agent.SetOnBreak()
		}

		wlog.Debug(fmt.Sprintf("agent %s[%d] has been changed status to \"%s\" %d sec", agent.Name(), agent.Id(), model.AGENT_STATE_FINE, timeout))
		return agent.SetStateFine(timeout, noAnswer)
	} else {
		wlog.Debug(fmt.Sprintf("agent %s[%d] has been changed status to \"%s\" %d sec", agent.Name(), agent.Id(), model.AGENT_STATE_REPORTING, at.WrapUpTime()))
		return agent.SetStateReporting(int(at.WrapUpTime()))
	}
}

func NewTeamManager(s store.Store) *teamManager {
	return &teamManager{
		store: s,
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
	team = &agentTeam{data: data}

	tm.cache.AddWithDefaultExpires(id, team)
	wlog.Debug(fmt.Sprintf("team [%d] %v store to cache", team.Id(), team.Name()))
	return team, err
}
