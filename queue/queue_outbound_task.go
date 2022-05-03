package queue

import (
	"fmt"
	"github.com/webitel/call_center/model"
)

type TaskOutboundQueue struct {
	BaseQueue
}

type TaskOutboundQueueSettings struct {
}

func NewTaskOutboundQueue(base BaseQueue) QueueObject {
	return &TaskOutboundQueue{
		BaseQueue: base,
	}
}

func (queue *TaskOutboundQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	fmt.Println("OK")
	return model.NewAppError("Queue", "todo", nil, "todo", 500)
}
