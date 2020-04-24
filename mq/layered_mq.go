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

func (l *LayeredMQ) QueueEvent() QueueEvent {
	return l.MQLayer.QueueEvent()
}

func (l *LayeredMQ) AgentChangeStatus(domainId int64, agentId int, e E) *model.AppError {
	return l.MQLayer.AgentChangeStatus(domainId, agentId, e)
}

func (l *LayeredMQ) ChannelEvent(channel string, domainId int64, agentId int, e E) *model.AppError {
	return l.MQLayer.ChannelEvent(channel, domainId, agentId, e)
}

func (l *LayeredMQ) AttemptEvent(channel string, domainId int64, queueId int, agentId *int, e E) *model.AppError {
	return l.MQLayer.AttemptEvent(channel, domainId, queueId, agentId, e)
}
