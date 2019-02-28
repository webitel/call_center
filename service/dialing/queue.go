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
}

type BaseQueue struct {
	id              int
	updatedAt       int64
	name            string
	resourceManager *ResourceManager
	queueManager    *QueueManager
}

func NewQueue(queueManager *QueueManager, resourceManager *ResourceManager, settings *model.Queue) (QueueObject, *model.AppError) {
	base := BaseQueue{
		id:              settings.Id,
		updatedAt:       settings.UpdatedAt,
		name:            "TODO-NAME",
		queueManager:    queueManager,
		resourceManager: resourceManager,
	}
	switch settings.Type {
	case model.QUEUE_TYPE_VOICE_BROADCAST:
		return NewVoiceBroadcastQueue(base, settings), nil
	default:
		return nil, model.NewAppError("Dialing.NewQueue", "dialing.queue.new_queue.app_error", nil,
			fmt.Sprintf("Queue type %v not implement", settings.Type), http.StatusInternalServerError)
	}
}

func (queue *BaseQueue) IsExpire(updatedAt int64) bool {
	return queue.updatedAt != updatedAt
}

func (queue *BaseQueue) Name() string {
	return queue.name
}
