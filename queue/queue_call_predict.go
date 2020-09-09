package queue

type PredictCallQueue struct {
	ProgressiveCallQueue
	CallingQueue
}

func NewPredictCallQueue(callQueue CallingQueue, settings ProgressiveCallQueueSettings) QueueObject {
	return &PredictCallQueue{
		CallingQueue: callQueue,
		ProgressiveCallQueue: ProgressiveCallQueue{
			CallingQueue:                 callQueue,
			ProgressiveCallQueueSettings: settings,
		},
	}
}
