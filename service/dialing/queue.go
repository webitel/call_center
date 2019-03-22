package dialing

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"net/http"
)

type QueueObject interface {
	Name() string
	IsExpire(int64) bool
	AddMemberAttempt(attempt *Attempt)
	FoundAgentForAttempt(attempt *Attempt)
	SetHangupCall(attempt *Attempt)
	Variables() map[string]string
}

type BaseQueue struct {
	id              int
	updatedAt       int64
	typeId          int8
	name            string
	resourceManager *ResourceManager
	queueManager    *QueueManager
	variables       map[string]string
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
	}
	switch settings.Type {
	case model.QUEUE_TYPE_INBOUND:
		return NewInboundQueue(CallingQueue{
			BaseQueue: base,
		}, settings), nil
	case model.QUEUE_TYPE_VOICE_BROADCAST:
		return NewVoiceBroadcastQueue(CallingQueue{
			BaseQueue: base,
		}, settings), nil
	default:
		return nil, model.NewAppError("Dialing.NewQueue", "dialing.queue.new_queue.app_error", nil,
			fmt.Sprintf("Queue type %v not implement", settings.Type), http.StatusInternalServerError)
	}
}

func (queue *BaseQueue) IsExpire(updatedAt int64) bool {
	return queue.updatedAt != updatedAt
}

func (queue *BaseQueue) Name() string {
	return fmt.Sprintf("%s-%s", queue.TypeName(), queue.name)
}

func (queue *BaseQueue) TypeName() string {
	switch queue.typeId {
	case model.QUEUE_TYPE_INBOUND:
		return "Inbound"
	case model.QUEUE_TYPE_VOICE_BROADCAST:
		return "Voice"
	default:
		return "NOT_IMPLEMENT"
	}
}

func (queue *BaseQueue) Variables() map[string]string {
	return queue.variables
}
