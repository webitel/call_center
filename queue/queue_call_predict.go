package queue

import "github.com/webitel/call_center/model"

type PredictCallQueue struct {
	CallingQueue
}

func NewPredictCallQueue(callQueue CallingQueue) QueueObject {
	return &PredictCallQueue{
		CallingQueue: callQueue,
	}
}

func (queue *PredictCallQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	return nil
}
