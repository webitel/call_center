package queue

import (
	workflow "buf.build/gen/go/webitel/workflow/protocolbuffers/go"
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"golang.org/x/sync/singleflight"
	"net/http"
	"sync"
)

const (
	MAX_TEAM_CACHE        = 10000
	MAX_TEAM_EXPIRE_CACHE = 60 * 60 * 24
)

var (
	teamGroupRequest singleflight.Group
)

type teamManager struct {
	store store.Store
	cache utils.ObjectCache
	sync.RWMutex
	mq  mq.MQ
	app App
}

type agentTeam struct {
	data        *model.Team
	teamManager *teamManager
	hook        HookHub
}

func NewTeam(info *model.Team, tm *teamManager) *agentTeam {
	return &agentTeam{
		data:        info,
		teamManager: tm,
		hook:        NewHookHub(info.Hooks),
	}
}

func NewTeamManager(app App, s store.Store, m mq.MQ) *teamManager {
	return &teamManager{
		store: s,
		mq:    m,
		cache: utils.NewLruWithParams(MAX_TEAM_CACHE, "team", MAX_TEAM_EXPIRE_CACHE, ""),
		app:   app,
	}
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

func (at *agentTeam) InviteChatTimeout() uint16 {
	return at.data.InviteChatTimeout
}

func (at *agentTeam) TaskAcceptTimeout() uint16 {
	return at.data.TaskAcceptTimeout
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

func (tm *teamManager) GetTeam(id int, updatedAt int64) (*agentTeam, *model.AppError) {
	tm.Lock() //TODO
	defer tm.Unlock()

	var team *agentTeam

	if t, ok := tm.cache.Get(id); ok {
		team = t.(*agentTeam)
		if updatedAt == 0 || team.data.UpdatedAt == updatedAt {
			return team, nil
		}
	}

	v, err, shared := teamGroupRequest.Do(fmt.Sprintf("%d-%d", id, updatedAt), func() (interface{}, error) {
		data, err := tm.store.Team().Get(id)
		if err != nil {
			return nil, err
		}

		return NewTeam(data, tm), nil
	})

	if err != nil {
		switch err.(type) {
		case *model.AppError:
			return nil, err.(*model.AppError)
		default:
			return nil, model.NewAppError("Queue", "queue.manager.team.get", nil, err.Error(), http.StatusInternalServerError)
		}
	}
	team = v.(*agentTeam)

	if !shared {
		tm.cache.AddWithDefaultExpires(id, team)
		wlog.Debug(fmt.Sprintf("team [%d] %v store to cache", team.Id(), team.Name()))
	}

	return team, nil
}

func (tm *teamManager) HookAgent(event string, agent agent_manager.AgentObject, teamUpdatedAt int64) *model.AppError {
	team, err := tm.GetTeam(agent.TeamId(), teamUpdatedAt)
	if err != nil {
		return err
	}

	if h, ok := team.hook.getByName(event); ok {
		// add params last attempt
		req := &workflow.StartFlowRequest{
			SchemaId:  h.SchemaId,
			DomainId:  agent.DomainId(),
			Variables: agent.HookData(),
		}

		id, err := tm.app.FlowManager().Queue().StartFlow(req)
		if err != nil {
			wlog.Error(fmt.Sprintf("hook \"%s\", error: %s", event, err.Error()))
		} else {
			wlog.Debug(fmt.Sprintf("hook \"%s\" external job_id: %s", event, id))
		}

		//call_manager.DUMP(req.Variables)
	}

	return nil
}

// FIXME store
func (tm *agentTeam) Answered(attempt *Attempt, agent agent_manager.AgentObject) {
	if attempt.queue != nil {
		attempt.queue.StartProcessingForm(attempt) //TODO
	}

	timestamp := model.GetMillis()
	attempt.SetState(model.MemberStateActive)
	e := NewAnsweredEvent(attempt, agent.UserId(), timestamp)
	err := tm.teamManager.mq.AgentChannelEvent(attempt.channel, attempt.domainId, attempt.QueueId(), agent.UserId(), e)
	if err != nil {
		attempt.Log(err.Error())
		return
	}
}

func (tm *agentTeam) Bridged(attempt *Attempt, agent agent_manager.AgentObject) {

	if attempt.queue != nil {
		attempt.queue.StartProcessingForm(attempt) //TODO
	}

	timestamp, err := tm.teamManager.store.Member().SetAttemptBridged(attempt.Id())
	if err != nil {
		attempt.Log(err.Error())
		return
	}
	attempt.SetState(model.MemberStateBridged)

	e := NewBridgedEventEvent(attempt, agent.UserId(), timestamp)
	err = tm.teamManager.mq.AgentChannelEvent(attempt.channel, attempt.domainId, attempt.QueueId(), agent.UserId(), e)
	if err != nil {
		attempt.Log(err.Error())
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
		if res.Status != "" {
			result = res.Status
		}

		vars = res.Variables
	}

	if res, err := tm.teamManager.store.Member().SetAttemptResult(attempt.Id(), result,
		model.ChannelStateWrapTime, t, vars, attempt.maxAttempts, attempt.waitBetween, attempt.perNumbers, attempt.description, attempt.stickyAgentId); err == nil {
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
		attempt.Log(err.Error())
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
		if attempt.Result() == "" {
			attempt.SetResult(AttemptResultSuccess)
		}
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
		s := attempt.Result()
		if s == "" {
			s = AttemptResultSuccess
		}
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
		attempt.Log(err.Error())
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
		attempt.Log(err.Error())
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
		attempt.Log(err.Error())
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
		attempt.Log(err.Error())
		return
	}
}

func (tm *agentTeam) MissedAgentAndWaitingAttempt(attempt *Attempt, agent agent_manager.AgentObject) {
	missed, err := tm.teamManager.store.Member().SetAttemptMissedAgent(attempt.Id(), int(tm.NoAnswerDelayTime()))
	if err != nil {
		attempt.Log(err.Error())
		return
	}

	tm.MissedAgent(missed, attempt, agent)
	attempt.agent = nil
	attempt.agentChannel = nil
}

func (tm *agentTeam) WaitingAgentAndWaitingAttempt(attempt *Attempt, agent agent_manager.AgentObject) {
	err := tm.teamManager.store.Member().SetAttemptWaitingAgent(attempt.Id(), int(tm.NoAnswerDelayTime()))
	if err != nil {
		attempt.Log(err.Error())
		return
	}

	e := NewWaitingChannelEvent(attempt.channel, agent.UserId(), model.NewInt64(attempt.Id()), model.GetMillis())
	err = tm.teamManager.mq.AgentChannelEvent(attempt.channel, agent.DomainId(), attempt.QueueId(), agent.UserId(), e)

	attempt.agent = nil
	attempt.agentChannel = nil

	if err != nil {
		attempt.Log(err.Error())
		return
	}
}

func (tm *agentTeam) SetAgentMaxNoAnswer(agent agent_manager.AgentObject) {
	if err := tm.teamManager.app.SetAgentBreakOut(agent); err != nil {
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
		attempt.Log(err.Error())
		return
	}

	return
}
