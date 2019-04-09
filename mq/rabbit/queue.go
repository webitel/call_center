package rabbit

import (
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
)

type RQueueEventMQ struct {
	amqp *AMQP
}

func NewQueueMQ(amqp *AMQP) mq.QueueEvent {
	return &RQueueEventMQ{amqp}
}

func (r RQueueEventMQ) SendChangedLength(e *model.QueueEventCount) *model.AppError {
	return r.amqp.SendJSON(r.amqp.getId(model.MQ_QUEUE_COUNT_EVENT_PREFIX), []byte(e.ToJSON()))
}
