package rabbit

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
)

type RQueueEventMQ struct {
	amqp mq.MQ
}

func NewQueueMQ(amqp mq.MQ) mq.QueueEvent {
	return &RQueueEventMQ{amqp}
}

func (a *AMQP) QueueUpdateListMembers(channel string, domainId int64, queueId int, userId int64, e mq.E) *model.AppError {
	return a.SendJSON(fmt.Sprintf("events.channel.%s.%d.%d.%d", channel, domainId, queueId, userId), []byte(e.ToJSON()))
}
