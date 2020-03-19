package rabbit

import (
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
)

type RQueueEventMQ struct {
	amqp mq.MQ
}

func NewQueueMQ(amqp mq.MQ) mq.QueueEvent {
	return &RQueueEventMQ{amqp}
}

func (r RQueueEventMQ) SendChangedLength(e *model.QueueEventCount) *model.AppError {
	//return r.amqp.SendJSON(getId(model.MQ_QUEUE_COUNT_EVENT_PREFIX), []byte(e.ToJSON()))
	return nil
}
