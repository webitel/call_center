package queue

import (
	"fmt"
	"github.com/webitel/call_center/model"
)

type ProgressiveCallQueue struct {
	CallingQueue
}

func NewProgressiveCallQueue(callQueue CallingQueue) QueueObject {
	return &ProgressiveCallQueue{
		CallingQueue: callQueue,
	}
}

func (queue *ProgressiveCallQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	fmt.Println(attempt.Id(), " >>>> ", attempt.agent.Id())
	return nil
}
