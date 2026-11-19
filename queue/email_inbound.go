package queue

import (
	"net/http"

	"github.com/webitel/call_center/model"
)

// InboundEmailQueue holds Email attempts joined by EmailJoinToQueue.
type InboundEmailQueue struct {
	BaseQueue
}

func NewInboundEmailQueue(base BaseQueue) QueueObject {
	return &InboundEmailQueue{BaseQueue: base}
}

// DistributeAttempt fails until agent distribution for Email is implemented.
func (queue *InboundEmailQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	return model.NewAppError("InboundEmailQueue.DistributeAttempt", "queue.email.distribute.not_implemented", nil,
		"email distribution is not implemented", http.StatusNotImplemented)
}
