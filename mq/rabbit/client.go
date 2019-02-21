package rabbit

import (
	"fmt"
	"github.com/streadway/amqp"
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
	"os"
	"time"
)

const (
	MAX_ATTEMPTS_CONNECT = 100
	RECONNECT_SEC        = 5
)

type AMQP struct {
	settings           *model.MQSettings
	connection         *amqp.Connection
	channel            *amqp.Channel
	connectionAttempts int
}

func NewRabbitMQ(settings model.MQSettings) mq.LayeredMQLayer {
	mq_ := &AMQP{
		settings: &settings,
	}
	go mq_.initConnection()

	return mq_
}

func (a *AMQP) initConnection() {
	var err error
	if a.settings.Url == nil {
		mlog.Critical(fmt.Sprintf("Failed settings AMQP connection url"))
		time.Sleep(time.Second)
		os.Exit(1)
	}
	if a.connectionAttempts >= MAX_ATTEMPTS_CONNECT {
		mlog.Critical(fmt.Sprintf("Failed to open AMQP connection..."))
		time.Sleep(time.Second)
		os.Exit(1)
	}
	a.connectionAttempts++
	a.connection, err = amqp.Dial(*a.settings.Url)
	if err != nil {
		mlog.Critical(fmt.Sprintf("Failed to open AMQP connection to err:%v", err.Error()))
		time.Sleep(time.Second * RECONNECT_SEC)
		a.initConnection()
	} else {
		a.connectionAttempts = 0
		a.channel, err = a.connection.Channel()
		if err != nil {
			mlog.Critical(fmt.Sprintf("Failed to open AMQP channel to err:%v", err.Error()))
			time.Sleep(time.Second)
			os.Exit(1)
		}
	}
}

func (a *AMQP) Close() {
	if a.channel != nil {
		a.channel.Close()
		mlog.Debug("Close AMQP channel")
	}

	if a.connection != nil {
		a.connection.Close()
		mlog.Debug("Close AMQP connection")
	}
}

func (a *AMQP) Send(name string, data map[string]interface{}) *model.AppError {
	return nil
}
