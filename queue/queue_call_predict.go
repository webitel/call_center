package queue

type PredictCallQueue struct {
	CallingQueue
}

func NewPredictCallQueue(callQueue CallingQueue) QueueObject {
	return &PredictCallQueue{
		CallingQueue: callQueue,
	}
}

func (queue *PredictCallQueue) DistributeAttempt(attempt *Attempt) {

}
