package queue

import "github.com/webitel/call_center/model"

type EmailQueue struct {
	BaseQueue
}

type InboundEmailQueue struct {
}

func (queue *InboundEmailQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	return nil
}
