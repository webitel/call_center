package queue

type PredictCallQueue struct {
	ProgressiveCallQueue
	CallingQueue
}

func NewPredictCallQueue(callQueue CallingQueue) QueueObject {
	return &PredictCallQueue{
		CallingQueue: callQueue,
		ProgressiveCallQueue: ProgressiveCallQueue{
			CallingQueue: callQueue,
		},
	}
}
