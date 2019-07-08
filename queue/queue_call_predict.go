package queue

type PredictCallQueue struct {
	CallingQueue
}

func NewPredictCallQueue(callQueue CallingQueue) QueueObject {
	return &PredictCallQueue{
		CallingQueue: callQueue,
	}
}

func (queue *PredictCallQueue) RouteAgentToAttempt(attempt *Attempt) {

}

func (queue *PredictCallQueue) JoinAttempt(attempt *Attempt) {

}

func (queue *PredictCallQueue) TimeoutAttempt(attempt *Attempt) {

}
