package queue

type ProgressiveCallQueue struct {
	CallingQueue
}

func NewProgressiveCallQueue(callQueue CallingQueue) QueueObject {
	return &ProgressiveCallQueue{
		CallingQueue: callQueue,
	}
}

func (queue *ProgressiveCallQueue) RouteAgentToAttempt(attempt *Attempt) {

}

func (queue *ProgressiveCallQueue) JoinAttempt(attempt *Attempt) {

}

func (queue *ProgressiveCallQueue) TimeoutAttempt(attempt *Attempt) {

}
