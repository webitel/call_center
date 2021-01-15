package queue

import (
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/chat"
	"github.com/webitel/call_center/model"
	"github.com/webitel/flow_manager/client"
	"github.com/webitel/wlog"
	"net/http"
)

type QueueObject interface {
	Name() string
	IsExpire(int64) bool
	TypeName() string

	DistributeAttempt(attempt *Attempt) *model.AppError

	Variables() map[string]string
	Domain() string
	DomainId() int64
	Channel() string
	Id() int
	AppId() string
}

type BaseQueue struct {
	channel         string
	id              int
	updatedAt       int64
	domainId        int64
	domainName      string
	typeId          int8
	name            string
	resourceManager *ResourceManager
	queueManager    *QueueManager
	variables       map[string]string
	timeout         uint16
	teamId          *int
	schemaId        *int
	ringtone        *model.RingtoneFile
	doSchema        *int32
	afterSchemaId   *int32
}

func NewQueue(queueManager *QueueManager, resourceManager *ResourceManager, settings *model.Queue) (QueueObject, *model.AppError) {
	base := BaseQueue{
		channel:         settings.Channel(),
		id:              settings.Id,
		updatedAt:       settings.UpdatedAt,
		typeId:          int8(settings.Type),
		domainId:        settings.DomainId,
		domainName:      settings.DomainName,
		name:            settings.Name,
		queueManager:    queueManager,
		resourceManager: resourceManager,
		variables:       settings.Variables,
		timeout:         settings.Timeout,
		teamId:          settings.TeamId,
		schemaId:        settings.SchemaId,
		doSchema:        settings.DoSchemaId,
		afterSchemaId:   settings.AfterSchemaId,
	}

	if settings.RingtoneId != nil && settings.RingtoneType != nil {
		base.ringtone = &model.RingtoneFile{
			Id:   *settings.RingtoneId,
			Type: *settings.RingtoneType,
		}
	}

	switch settings.Type {
	case model.QUEUE_TYPE_OFFLINE:
		return NewOfflineCallQueue(CallingQueue{
			BaseQueue: base,
		}, QueueOfflineSettingsFromBytes(settings.Payload)), nil
	case model.QUEUE_TYPE_INBOUND:
		inboundSettings := model.QueueInboundSettingsFromBytes(settings.Payload)
		return NewInboundQueue(CallingQueue{
			BaseQueue: base,
		}, inboundSettings), nil

	case model.QUEUE_TYPE_IVR:
		return NewIVRQueue(CallingQueue{
			BaseQueue: base,
		}, QueueIVRSettingsFromBytes(settings.Payload)), nil

	case model.QUEUE_TYPE_PREVIEW:
		return NewPreviewCallQueue(CallingQueue{
			BaseQueue: base,
		}, PreviewSettingsFromBytes(settings.Payload)), nil

	case model.QUEUE_TYPE_PROGRESSIVE:
		return NewProgressiveCallQueue(CallingQueue{
			BaseQueue: base,
		}, ProgressiveSettingsFromBytes(settings.Payload)), nil

	case model.QUEUE_TYPE_PREDICT:
		return NewPredictCallQueue(CallingQueue{
			BaseQueue: base,
		}, ProgressiveSettingsFromBytes(settings.Payload)), nil

	case model.QueueTypeChat:
		return NewInboundChatQueue(base, InboundChatQueueFromBytes(settings.Payload)), nil
	case model.QueueTypeAgentTask:
		return NewTaskAgentQueue(base), nil

	default:
		return nil, model.NewAppError("Dialing.NewQueue", "dialing.queue.new_queue.app_error", nil,
			fmt.Sprintf("Queue type %v not implement", settings.Type), http.StatusInternalServerError)
	}
}

func (queue *BaseQueue) AppId() string {
	return queue.queueManager.app.GetInstanceId()
}

func (queue *BaseQueue) IsExpire(updatedAt int64) bool {
	return queue.updatedAt != updatedAt
}

func (queue *BaseQueue) FlowManager() client.FlowManager {
	return queue.queueManager.app.FlowManager()
}

func (queue *BaseQueue) Name() string {
	return queue.name
}

func (queue *BaseQueue) Timeout() uint16 {
	return queue.timeout
}

func (queue *BaseQueue) TeamManager() *teamManager {
	return queue.queueManager.teamManager
}

func (queue *BaseQueue) GetTeam(attempt *Attempt) (*agentTeam, *model.AppError) {
	if queue.teamId != nil && attempt.TeamUpdatedAt() != nil {
		return queue.TeamManager().GetTeam(*queue.teamId, *attempt.TeamUpdatedAt())
	}

	return nil, model.NewAppError("BaseQueue.GetTeam", "queue.team.get_by_id.app_error", nil, "Not found parameters", http.StatusInternalServerError)
}

func (queue *BaseQueue) TypeName() string {
	switch queue.typeId {
	case model.QUEUE_TYPE_OFFLINE:
		return "offline"
	case model.QUEUE_TYPE_INBOUND:
		return "inbound"
	case model.QUEUE_TYPE_IVR:
		return "ivr"
	case model.QUEUE_TYPE_PREVIEW:
		return "preview"
	case model.QUEUE_TYPE_PROGRESSIVE:
		return "progressive"
	case model.QUEUE_TYPE_PREDICT:
		return "predictive"
	case model.QueueTypeChat:
		return "inbound chat"
	case model.QueueTypeAgentTask:
		return "task"
	default:
		return "NOT_IMPLEMENT"
	}
}

func (queue *BaseQueue) Variables() map[string]string {
	return queue.variables
}

func (q *BaseQueue) Domain() string {
	return q.domainName
}

func (q *BaseQueue) DomainId() int64 {
	return q.domainId
}

func (queue *BaseQueue) Id() int {
	return queue.id
}

func (queue *BaseQueue) CallManager() call_manager.CallManager {
	return queue.queueManager.callManager
}

func (queue *BaseQueue) ChatManager() *chat.ChatManager {
	return queue.queueManager.app.ChatManager()
}

func (queue *BaseQueue) AgentManager() agent_manager.AgentManager {
	return queue.queueManager.agentManager
}

func (queue *BaseQueue) Channel() string {
	return queue.channel
}

func (queue *BaseQueue) Hook(agent agent_manager.AgentObject, e model.Event) {
	if err := queue.queueManager.mq.AgentChannelEvent(queue.Channel(), queue.domainId, queue.id, agent.UserId(), e); err != nil {
		wlog.Error(err.Error())
	}
}

func (tm *agentTeam) Offering(attempt *Attempt, agent agent_manager.AgentObject, aChannel, mChannel Channel) {
	agentId := model.NewInt(agent.Id())
	agentCallId := model.NewString(aChannel.Id())
	var mCallId *string = nil
	if mChannel != nil {
		mCallId = model.NewString(mChannel.Id())
	}

	timestamp, err := tm.teamManager.store.Member().SetAttemptOffering(attempt.Id(), agentId, agentCallId, mCallId, &attempt.communication.Destination, attempt.communication.Display)
	if err != nil {
		wlog.Error(err.Error())
		return
	}
	e := NewOfferingEvent(attempt, agent.UserId(), timestamp, aChannel, mChannel)
	err = tm.teamManager.mq.AgentChannelEvent(attempt.channel, attempt.domainId, attempt.QueueId(), agent.UserId(), e)
	if err != nil {
		wlog.Error(err.Error())
		return
	}
}

func (tm *agentTeam) Cancel(attempt *Attempt, agent agent_manager.AgentObject, maxAttempts uint, sleep uint64) {
	//SetAttemptAbandonedWithParams
	//timestamp, err := tm.teamManager.store.Member().SetAttemptAbandoned(attempt.Id())
	timestamp, err := tm.teamManager.store.Member().SetAttemptAbandonedWithParams(attempt.Id(), maxAttempts, sleep)
	if err != nil {
		wlog.Error(err.Error())

		return
	}

	attId := model.NewInt64(attempt.Id())
	e := NewWaitingChannelEvent(attempt.channel, agent.UserId(), attId, timestamp)
	err = tm.teamManager.mq.AgentChannelEvent(attempt.channel, attempt.domainId, attempt.QueueId(), agent.UserId(), e)
	if err != nil {
		wlog.Error(err.Error())
	}
}

//FIXME store
func (tm *agentTeam) Answered(attempt *Attempt, agent agent_manager.AgentObject) {
	timestamp := model.GetMillis()
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

	e := NewBridgedEventEvent(attempt, agent.UserId(), timestamp)
	err = tm.teamManager.mq.AgentChannelEvent(attempt.channel, attempt.domainId, attempt.QueueId(), agent.UserId(), e)
	if err != nil {
		wlog.Error(err.Error())
		return
	}
}

func (tm *agentTeam) Reporting(attempt *Attempt, agent agent_manager.AgentObject, agentSendReporting bool) {
	if agentSendReporting {
		// FIXME
		attempt.SetResult(AttemptResultSuccess)
		return
	}

	if !tm.PostProcessing() {
		// FIXME
		attempt.SetResult(AttemptResultSuccess)
		if timestamp, err := tm.teamManager.store.Member().SetAttemptResult(attempt.Id(), "success", 30,
			model.ChannelStateWrapTime, int(tm.WrapUpTime())); err == nil {
			e := NewWrapTimeEventEvent(attempt, agent.UserId(), timestamp, timestamp+(int64(tm.WrapUpTime()*1000)), false)
			err = tm.teamManager.mq.AgentChannelEvent(attempt.channel, attempt.domainId, attempt.QueueId(), agent.UserId(), e)
			if err != nil {
				wlog.Error(err.Error())
			}
		} else {
			wlog.Error(err.Error())
		}
		return
	}

	timeoutSec := tm.PostProcessingTimeout()

	if agent.IsOnDemand() {
		timeoutSec = 0
	}

	attempt.SetResult(AttemptResultPostProcessing)
	timestamp, err := tm.teamManager.store.Member().SetAttemptReporting(attempt.Id(), timeoutSec)
	if err != nil {
		wlog.Error(err.Error())
		return
	}

	e := NewWrapTimeEventEvent(attempt, agent.UserId(), timestamp, timestamp+(int64(timeoutSec*1000)), true)
	err = tm.teamManager.mq.AgentChannelEvent(attempt.channel, attempt.domainId, attempt.QueueId(), agent.UserId(), e)
	if err != nil {
		wlog.Error(err.Error())
		return
	}

	wlog.Debug(fmt.Sprintf("attempt [%d] wait callback result for agent \"%s\"", attempt.Id(), agent.Name()))
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
}

func (tm *agentTeam) SetAgentMaxNoAnswer(agent agent_manager.AgentObject) {
	if err := agent.SetOnBreak(); err != nil {
		wlog.Error(fmt.Sprintf("agent \"%s\" change to pause error %s", agent.Name(), err.Error()))
	} else {
		wlog.Debug(fmt.Sprintf("agent \"%s\" changed status to pause, maximum no answers in team \"%s\"", agent.Name(), tm.Name()))
	}

}
