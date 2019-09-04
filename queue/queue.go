package queue

import (
	"fmt"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
	"net/http"
)

type QueueObject interface {
	Name() string
	IsExpire(int64) bool

	DistributeAttempt(attempt *Attempt)

	Variables() map[string]string
	Domain() string
	Id() int
}

type BaseQueue struct {
	id              int
	updatedAt       int64
	typeId          int8
	name            string
	resourceManager *ResourceManager
	queueManager    *QueueManager
	variables       map[string]string
	timeout         uint16
	teamId          *int64
}

func NewQueue(queueManager *QueueManager, resourceManager *ResourceManager, settings *model.Queue) (QueueObject, *model.AppError) {
	base := BaseQueue{
		id:              settings.Id,
		typeId:          int8(settings.Type),
		updatedAt:       settings.UpdatedAt,
		name:            settings.Name,
		queueManager:    queueManager,
		resourceManager: resourceManager,
		variables:       settings.Variables,
		timeout:         settings.Timeout,
		teamId:          settings.TeamId,
	}
	switch settings.Type {
	case model.QUEUE_TYPE_INBOUND:
		return NewInboundQueue(CallingQueue{
			BaseQueue: base,
		}, settings), nil

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

func (queue *BaseQueue) SipRouterAddr() string {
	return "sip:192.168.177.11"
}

func (queue *BaseQueue) Name() string {
	return fmt.Sprintf("%s-%s", queue.TypeName(), queue.name)
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

func (qeueu *BaseQueue) Domain() string {
	return "10.10.10.144" //todo add domain
}

func (queue *BaseQueue) Id() int {
	return queue.id
}

func (queue *BaseQueue) CallManager() call_manager.CallManager {
	return queue.queueManager.callManager
}
