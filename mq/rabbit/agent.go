package rabbit

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
)

func (a *AMQP) AgentChangeStatus(domainId int64, userId int64, e mq.E) *model.AppError {
	return a.SendJSON(fmt.Sprintf("events.status.%d.%d", domainId, userId), []byte(e.ToJSON()))
}

func (a *AMQP) AgentChannelEvent(channel string, domainId int64, queueId int, userId int64, e mq.E) *model.AppError {
	return a.SendJSON(fmt.Sprintf("events.channel.%s.%d.%d.%d", channel, domainId, queueId, userId), []byte(e.ToJSON()))
}
