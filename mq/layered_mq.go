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

func (l *LayeredMQ) Send(name string, data map[string]interface{}) *model.AppError {
	return l.MQLayer.Send(name, data)
}

func (l *LayeredMQ) Close() {
	l.MQLayer.Close()
}
