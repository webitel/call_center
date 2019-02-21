package rabbit

import (
	"encoding/json"
	"fmt"
	"github.com/streadway/amqp"
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
	"net/http"
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
	queueName          string
	connectionAttempts int
	stopping           bool
}

func NewRabbitMQ(settings model.MQSettings) mq.LayeredMQLayer {
	mq_ := &AMQP{
		settings: &settings,
	}
	mq_.initConnection()

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
		a.initQueues()
		if err != nil {
			mlog.Critical(fmt.Sprintf("Failed to open AMQP channel to err:%v", err.Error()))
			time.Sleep(time.Second)
			os.Exit(1)
		}
	}
}

func (a *AMQP) initQueues() {
	var err error
	var queue amqp.Queue
	err = a.channel.ExchangeDeclare(
		model.EXCHANGE_MQ,
		"topic",
		true,
		false,
		false,
		false,
		nil,
	)

	if err != nil {
		mlog.Critical(fmt.Sprintf("Failed to declare AMQP exchange to err:%v", err.Error()))
		time.Sleep(time.Second)
		os.Exit(1)
	}

	queue, err = a.channel.QueueDeclare(fmt.Sprintf("cc.%s", model.NewId()),
		true, false, true, false, nil)
	if err != nil {
		mlog.Critical(fmt.Sprintf("Failed to declare AMQP queue %v to err:%v", model.QUEUE_MQ, err.Error()))
		time.Sleep(time.Second)
		os.Exit(1)
	}

	a.queueName = queue.Name
	mlog.Debug(fmt.Sprintf("Success declare queue %v, connected consumers %v", queue.Name, queue.Consumers))
	a.subscribe()
}

func (a *AMQP) subscribe() {
	err := a.channel.QueueBind(a.queueName, "*.CHANNEL_CREATE.*.*.*", model.EXCHANGE_MQ, false, nil)
	if err != nil {
		panic(err)
	}

	err = a.channel.QueueBind(a.queueName, "*.CHANNEL_HANGUP.*.*.*", model.EXCHANGE_MQ, false, nil)
	if err != nil {
		panic(err)
	}

	err = a.channel.QueueBind(a.queueName, "*.CHANNEL_PARK.*.*.*", model.EXCHANGE_MQ, false, nil)
	if err != nil {
		panic(err)
	}

	msgs, err := a.channel.Consume(
		a.queueName,
		"",
		false,
		false,
		false,
		false,
		nil,
	)
	if err != nil {
		panic(err)
	}

	go func() {
		var err error
		for m := range msgs {
			e := &mq.Event{}
			err = json.Unmarshal(m.Body, e)
			if err != nil {
				mlog.Warn(err.Error())
				mlog.Warn(fmt.Sprintf("Failed parse json event, skip %s", m.Body))
				continue
			}
			mlog.Debug(fmt.Sprintf("Receive event %v", e.Name()))
			m.Ack(false)
		}

		if !a.stopping {
			a.initConnection()
		}
	}()
}

func (a *AMQP) Close() {
	mlog.Debug("AMQP receive stop client")
	a.stopping = true
	if a.channel != nil {
		a.channel.Close()
		mlog.Debug("Close AMQP channel")
	}

	if a.connection != nil {
		a.connection.Close()
		mlog.Debug("Close AMQP connection")
	}
}

func (a *AMQP) Bind(uuid string) *model.AppError {
	err := a.channel.QueueBind(model.QUEUE_MQ, makeRK(uuid), model.EXCHANGE_MQ, true, nil)
	if err != nil {
		return model.NewAppError("Bind", "mq.bind.app_error", nil, "",
			http.StatusInternalServerError)
	}
	return nil
}

func (a *AMQP) UnBind(uuid string) *model.AppError {
	err := a.channel.QueueUnbind(model.QUEUE_MQ, makeRK(uuid), model.EXCHANGE_MQ, nil)
	if err != nil {
		return model.NewAppError("Bind", "mq.bind.app_error", nil, "",
			http.StatusInternalServerError)
	}
	return nil
}

func (a *AMQP) Send(name string, data map[string]interface{}) *model.AppError {
	return nil
}

func makeRK(uuid string) string {
	return fmt.Sprintf("*.*.*.*.%s", uuid)
}
