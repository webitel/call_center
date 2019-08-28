package queue

import "fmt"

type ProgressiveCallQueue struct {
	CallingQueue
}

func NewProgressiveCallQueue(callQueue CallingQueue) QueueObject {
	return &ProgressiveCallQueue{
		CallingQueue: callQueue,
	}
}

func (queue *ProgressiveCallQueue) DistributeAttempt(attempt *Attempt) {
	fmt.Println(attempt.Id(), " >>>> ", attempt.agent.Id())
}
