package rabbit

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
)

func (a *AMQP) AgentChangeStatus(domainId int64, agentId int, e mq.E) *model.AppError {
	return a.SendJSON(fmt.Sprintf("events.status.%d.%d", domainId, agentId), []byte(e.ToJSON()))
}

func (a *AMQP) ChannelEvent(channel string, domainId int64, agentId int, e mq.E) *model.AppError {
	return a.SendJSON(fmt.Sprintf("events.channel.%s.%d..%d", channel, domainId, agentId), []byte(e.ToJSON()))
}

func (a *AMQP) AttemptEvent(channel string, domainId int64, queueId int, agentId *int, e mq.E) *model.AppError {
	if agentId != nil {
		return a.SendJSON(fmt.Sprintf("events.channel.%s.%d.%d.%d", channel, domainId, queueId, *agentId), []byte(e.ToJSON()))
	} else {
		return a.SendJSON(fmt.Sprintf("events.channel.%s.%d.%d.", channel, domainId, queueId), []byte(e.ToJSON()))
	}
}
