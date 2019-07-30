package rabbit

import (
	"encoding/json"
	"fmt"
	"github.com/streadway/amqp"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
	"github.com/webitel/wlog"
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
	callEvent          chan model.Event
	queueEvent         mq.QueueEvent
}

func NewRabbitMQ(settings model.MQSettings, nodeName string) mq.LayeredMQLayer {
	mq_ := &AMQP{
		settings:  &settings,
		callEvent: make(chan model.Event),
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
		wlog.Critical(fmt.Sprintf("Failed to open AMQP connection..."))
		time.Sleep(time.Second)
		os.Exit(1)
	}
	a.connectionAttempts++
	a.connection, err = amqp.Dial(*a.settings.Url)
	if err != nil {
		wlog.Critical(fmt.Sprintf("Failed to open AMQP connection to err:%v", err.Error()))
		time.Sleep(time.Second * RECONNECT_SEC)
		a.initConnection()
	} else {
		a.connectionAttempts = 0
		a.channel, err = a.connection.Channel()
		if err != nil {
			wlog.Critical(fmt.Sprintf("Failed to open AMQP channel to err:%v", err.Error()))
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
		model.MQ_CALL_EXCHANGE,
		"direct",
		true,
		false,
		false,
		false,
		nil,
	)

	if err != nil {
		wlog.Critical(fmt.Sprintf("Failed to declare AMQP exchange to err:%v", err.Error()))
		time.Sleep(time.Second)
		os.Exit(EXIT_DECLARE_EXCHANGE)
	}

	queue, err = a.channel.QueueDeclare(fmt.Sprintf("cc.%s", model.NewId()),
		true, false, true, false, nil)
	if err != nil {
		wlog.Critical(fmt.Sprintf("Failed to declare AMQP queue %v to err:%v", model.QUEUE_MQ, err.Error()))
		time.Sleep(time.Second)
		os.Exit(EXIT_DECLARE_QUEUE)
	}

	a.queueName = queue.Name
	wlog.Debug(fmt.Sprintf("Success declare queue %v, connected consumers %v", queue.Name, queue.Consumers))
	a.subscribe()
}

func (a *AMQP) subscribe() {
	err := a.channel.QueueBind(a.queueName, fmt.Sprintf("callcenter.%s", a.nodeName), model.MQ_CALL_EXCHANGE, false, nil)
	if err != nil {
		wlog.Critical(fmt.Sprintf("Error binding queue %s to %s: %s", a.queueName, model.MQ_CALL_EXCHANGE, err.Error()))
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
		wlog.Critical(fmt.Sprintf("Error create consume for queue %s: %s", a.queueName, err.Error()))
		time.Sleep(time.Second)
		os.Exit(EXIT_BIND)
	}

	go func() {
		for m := range msgs {
			if m.ContentType != "text/json" {
				wlog.Warn(fmt.Sprintf("Failed receive event content type: %v\n%s", m.ContentType, m.Body))
				continue
			}

			switch m.Exchange {
			case model.MQ_CALL_EXCHANGE:
				a.handleCallMessage(m.Body)
			default:
				wlog.Warn(fmt.Sprintf("unable to parse event, not found exchange", m.Exchange))
			}
			m.Ack(false)
		}

		if !a.stopping {
			a.initConnection()
		}
	}()
}

func (a *AMQP) handleCallMessage(data []byte) {
	e := make(model.Event)
	if err := json.Unmarshal(data, &e); err != nil {
		wlog.Error(fmt.Sprintf("parse error: %s", err.Error()))
		return
	}

	a.callEvent <- e
}

func (a *AMQP) Close() {
	wlog.Debug("AMQP receive stop client")
	a.stopping = true
	if a.channel != nil {
		a.channel.Close()
		wlog.Debug("Close AMQP channel")
	}

	if a.connection != nil {
		a.connection.Close()
		wlog.Debug("Close AMQP connection")
	}
}

func (a *AMQP) SendJSON(key string, data []byte) *model.AppError {
	//todo, check connection
	err := a.channel.Publish(
		model.MQ_CALL_EXCHANGE,
		key,
		false,
		false,
		amqp.Publishing{
			ContentType: "text/json",
			Body:        data,
		},
	)
	if err != nil {
		return model.NewAppError("SendJSON", "mq.send_json.app_error", nil, err.Error(),
			http.StatusInternalServerError)
	}
	return nil
}

func (a *AMQP) ConsumeCallEvent() <-chan model.Event {
	return a.callEvent
}

func getId(name string) string {
	return model.MQ_EVENT_PREFIX + "." + name
}
