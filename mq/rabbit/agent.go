package rabbit

import (
	"fmt"
	"github.com/streadway/amqp"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
	"net/http"
)

func (a *AMQP) AgentChangeStatus(domainId int64, userId int64, e mq.E) *model.AppError {
	return a.SendJSON(fmt.Sprintf("events.status.%d.%d", domainId, userId), []byte(e.ToJSON()))
}

func (a *AMQP) AgentChannelEvent(channel string, domainId int64, queueId int, userId int64, e mq.E) *model.AppError {
	return a.SendJSON(fmt.Sprintf("events.channel.%s.%d.%d.%d", channel, domainId, queueId, userId), []byte(e.ToJSON()))
}

func (a *AMQP) SendNotification(domainId int64, event *model.Notification) *model.AppError {
	err := a.channel.Publish(model.EngineExchange, fmt.Sprintf("notification.%d", domainId), false, false, amqp.Publishing{
		ContentType: "text/json",
		Body:        []byte(event.ToJson()),
	})
	if err != nil {
		return model.NewAppError("AMQP.SendNotification", "amqp.notification.publish.app_error", nil, err.Error(), http.StatusInternalServerError)
	}
	return nil
}
