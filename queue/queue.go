package queue

import (
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
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
	}
	switch settings.Type {
	case model.QUEUE_TYPE_OFFLINE:
		return NewOfflineCallQueue(CallingQueue{
			BaseQueue: base,
		}), nil
	case model.QUEUE_TYPE_INBOUND:
		inboundSettings := model.QueueInboundSettingsFromBytes(settings.Payload)
		return NewInboundQueue(CallingQueue{
			BaseQueue: base,
		}, inboundSettings), nil

	case model.QUEUE_TYPE_IVR:
		ivrSettings := model.QueueIVRSettingsFromBytes(settings.Payload)
		return NewIVRQueue(CallingQueue{
			BaseQueue: base,
			params:    ivrSettings.QueueDialingSettings,
		}, ivrSettings.Amd), nil

	case model.QUEUE_TYPE_PREVIEW:
		return NewPreviewCallQueue(CallingQueue{
			BaseQueue: base,
		}), nil

	case model.QUEUE_TYPE_PROGRESSIVE:
		return NewProgressiveCallQueue(CallingQueue{
			BaseQueue: base,
		}), nil

	case model.QUEUE_TYPE_PREDICT:
		return NewPredictCallQueue(CallingQueue{
			BaseQueue: base,
		}), nil

	default:
		return nil, model.NewAppError("Dialing.NewQueue", "dialing.queue.new_queue.app_error", nil,
			fmt.Sprintf("Queue type %v not implement", settings.Type), http.StatusInternalServerError)
	}
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

func (queue *BaseQueue) AgentManager() agent_manager.AgentManager {
	return queue.queueManager.agentManager
}

func (queue *BaseQueue) Channel() string {
	return queue.channel
}

func (queue *BaseQueue) Hook(agentId *int, e model.Event) {
	if err := queue.queueManager.mq.AttemptEvent(queue.Channel(), queue.domainId, queue.id, agentId, e); err != nil {
		wlog.Error(err.Error())
	}
}

func (tm *agentTeam) Offering(attempt *Attempt, agent agent_manager.AgentObject, aChannel, mChannel Channel) {
	agentId := model.NewInt(agent.Id())
	timestamp, err := tm.teamManager.store.Member().SetAttemptOffering(attempt.Id(), agentId)
	if err != nil {
		wlog.Error(err.Error())
		return
	}
	e := NewOfferingEvent(attempt, timestamp, aChannel, mChannel)
	err = tm.teamManager.mq.AttemptEvent(attempt.channel, attempt.domainId, attempt.QueueId(), agentId, e)
	if err != nil {
		wlog.Error(err.Error())
		return
	}
}

func (tm *agentTeam) Reporting(attempt *Attempt, agent agent_manager.AgentObject) {
	agentId := model.NewInt(agent.Id())

	if !tm.PostProcessing() {
		if timestamp, err := tm.teamManager.store.Member().SetAttemptResult2(attempt.Id(), "SUCCESS", 30,
			model.ChannelStateWrapTime, int(tm.WrapUpTime())); err == nil {
			e := NewWrapTimeEventEvent(attempt, timestamp, timestamp+(int64(tm.WrapUpTime()*1000)))
			err = tm.teamManager.mq.AttemptEvent(attempt.channel, attempt.domainId, attempt.QueueId(), agentId, e)
			if err != nil {
				wlog.Error(err.Error())
			}
		} else {
			wlog.Error(err.Error())
		}
		return
	}

	timestamp, err := tm.teamManager.store.Member().SetAttemptReporting(attempt.Id(), tm.PostProcessingTimeout())
	if err != nil {
		wlog.Error(err.Error())
		return
	}
	e := NewReportingEventEvent(attempt, timestamp, tm.PostProcessingTimeout())
	err = tm.teamManager.mq.AttemptEvent(attempt.channel, attempt.domainId, attempt.QueueId(), agentId, e)
	if err != nil {
		wlog.Error(err.Error())
		return
	}

	result := attempt.WaitTimeout()
	waiting := NewWaitingChannelEvent(model.NewInt64(attempt.Id()), result.Timestamp)
	err = tm.teamManager.mq.AttemptEvent(attempt.channel, attempt.domainId, attempt.QueueId(), agentId, waiting)
	if err != nil {
		wlog.Error(err.Error())
		return
	}
}

func (tm *agentTeam) Missed(attempt *Attempt, holdSec int, agent agent_manager.AgentObject) {
	agentId := model.NewInt(agent.Id())
	timestamp, err := tm.teamManager.store.Member().SetAttemptMissed(attempt.Id(), holdSec, int(tm.BusyDelayTime()))
	if err != nil {
		wlog.Error(err.Error())
		return
	}
	e := NewMissedEventEvent(attempt, timestamp, timestamp+(int64(tm.BusyDelayTime()*1000)))
	err = tm.teamManager.mq.AttemptEvent(attempt.channel, attempt.domainId, attempt.QueueId(), agentId, e)
	if err != nil {
		wlog.Error(err.Error())
		return
	}
}
