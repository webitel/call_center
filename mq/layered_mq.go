package mq

import (
	"context"
	"github.com/webitel/call_center/model"
)

type LayeredMQLayer interface {
	MQ
}

type LayeredMQ struct {
	context context.Context
	MQLayer LayeredMQLayer
}

func NewMQ(mq LayeredMQLayer) MQ {
	return &LayeredMQ{
		context: context.TODO(),
		MQLayer: mq,
	}
}

func (l *LayeredMQ) SendJSON(name string, data []byte) *model.AppError {
	return l.MQLayer.SendJSON(name, data)
}

func (l *LayeredMQ) Close() {
	l.MQLayer.Close()
}

func (l *LayeredMQ) ConsumeCallEvent() <-chan model.CallActionData {
	return l.MQLayer.ConsumeCallEvent()
}

func (l *LayeredMQ) ConsumeChatEvent() <-chan model.ChatEvent {
	return l.MQLayer.ConsumeChatEvent()
}

func (l *LayeredMQ) QueueEvent() QueueEvent {
	return l.MQLayer.QueueEvent()
}

func (l *LayeredMQ) AgentChangeStatus(domainId int64, userId int64, e E) *model.AppError {
	return l.MQLayer.AgentChangeStatus(domainId, userId, e)
}

func (l *LayeredMQ) AgentChannelEvent(channel string, domainId int64, queueId int, userId int64, e E) *model.AppError {
	return l.MQLayer.AgentChannelEvent(channel, domainId, queueId, userId, e)
}

func (l *LayeredMQ) SendNotification(domainId int64, event *model.Notification) *model.AppError {
	return l.MQLayer.SendNotification(domainId, event)
}
