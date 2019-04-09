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

const (
	EXIT_DECLARE_EXCHANGE = 110
	EXIT_DECLARE_QUEUE    = 111
	EXIT_BIND             = 112
)

type AMQP struct {
	settings           *model.MQSettings
	connection         *amqp.Connection
	channel            *amqp.Channel
	queueName          string
	nodeName           string
	connectionAttempts int
	stopping           bool
	callEvent          chan mq.Event
	queueEvent         mq.QueueEvent
}

func NewRabbitMQ(settings model.MQSettings, nodeName string) mq.LayeredMQLayer {
	mq_ := &AMQP{
		settings:  &settings,
		callEvent: make(chan mq.Event),
		nodeName:  nodeName,
	}
	mq_.queueEvent = NewQueueMQ(mq_)
	mq_.initConnection()

	return mq_
}

func (a *AMQP) QueueEvent() mq.QueueEvent {
	return a.queueEvent
}

func (a *AMQP) initConnection() {
	var err error

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
		} else {
			a.initQueues()
		}
	}
}

func (a *AMQP) initQueues() {
	var err error
	var queue amqp.Queue
	err = a.channel.ExchangeDeclare(
		model.EXCHANGE_MQ,
		"direct",
		true,
		false,
		false,
		false,
		nil,
	)

	if err != nil {
		mlog.Critical(fmt.Sprintf("Failed to declare AMQP exchange to err:%v", err.Error()))
		time.Sleep(time.Second)
		os.Exit(EXIT_DECLARE_EXCHANGE)
	}

	queue, err = a.channel.QueueDeclare(fmt.Sprintf("cc.%s", model.NewId()),
		true, false, true, false, nil)
	if err != nil {
		mlog.Critical(fmt.Sprintf("Failed to declare AMQP queue %v to err:%v", model.QUEUE_MQ, err.Error()))
		time.Sleep(time.Second)
		os.Exit(EXIT_DECLARE_QUEUE)
	}

	a.queueName = queue.Name
	mlog.Debug(fmt.Sprintf("Success declare queue %v, connected consumers %v", queue.Name, queue.Consumers))
	a.subscribe()
}

func (a *AMQP) subscribe() {
	err := a.channel.QueueBind(a.queueName, fmt.Sprintf("callcenter.%s", a.nodeName), model.EXCHANGE_MQ, false, nil)
	if err != nil {
		mlog.Critical(fmt.Sprintf("Error binding queue %s to %s: %s", a.queueName, model.EXCHANGE_MQ, err.Error()))
		time.Sleep(time.Second)
		os.Exit(EXIT_BIND)
	}

	msgs, err := a.channel.Consume(
		a.queueName,
		"",
		false,
		true,
		false,
		false,
		nil,
	)
	if err != nil {
		mlog.Critical(fmt.Sprintf("Error create consume for queue %s: %s", a.queueName, err.Error()))
		time.Sleep(time.Second)
		os.Exit(EXIT_BIND)
	}

	go func() {
		var err error
		for m := range msgs {
			if m.ContentType != "text/json" {
				mlog.Warn(fmt.Sprintf("Failed receive event content type: %v\n%s", m.ContentType, m.Body))
				continue
			}
			e := &REvent{}
			err = json.Unmarshal(m.Body, e)
			if err != nil {
				mlog.Warn(err.Error())
				mlog.Warn(fmt.Sprintf("Failed parse json event, skip %s", m.Body))
				continue
			}
			mlog.Debug(fmt.Sprintf("Receive event %v [%v]", e.Name(), e.Id()))
			a.callEvent <- e
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

func (a *AMQP) SendJSON(key string, data []byte) *model.AppError {
	err := a.channel.Publish(
		model.EXCHANGE_MQ,
		key,
		false,
		false,
		amqp.Publishing{
			ContentType: "text/json",
			Body:        data,
		},
	)
	if err != nil {
		return model.NewAppError("SendJSON", "mq.send_json.app_error", nil, "",
			http.StatusInternalServerError)
	}
	return nil
}

func (a *AMQP) ConsumeCallEvent() <-chan mq.Event {
	return a.callEvent
}

func getId(name string) string {
	return model.MQ_EVENT_PREFIX + "." + name
}
