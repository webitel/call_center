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
	settings           *model.MessageQueueSettings
	connection         *amqp.Connection
	channel            *amqp.Channel
	errorChan          chan *amqp.Error
	stop               chan struct{}
	stopped            chan struct{}
	queueName          string
	nodeName           string
	connectionAttempts int
	callEvent          chan model.CallActionData
	queueEvent         mq.QueueEvent
}

func NewRabbitMQ(settings model.MessageQueueSettings, nodeName string) mq.LayeredMQLayer {
	mq_ := &AMQP{
		settings:  &settings,
		errorChan: make(chan *amqp.Error, 1),
		stop:      make(chan struct{}),
		stopped:   make(chan struct{}),
		callEvent: make(chan model.CallActionData),
		nodeName:  nodeName,
	}
	mq_.queueEvent = NewQueueMQ(mq_)
	mq_.initConnection()
	go mq_.listen()
	return mq_
}

func (a *AMQP) QueueEvent() mq.QueueEvent {
	return a.queueEvent
}

func (a *AMQP) listen() {
	defer func() {
		wlog.Info("close amqp listener")
		close(a.stopped)
	}()
	wlog.Info("start amqp listener")

	for {
		select {
		case err, ok := <-a.errorChan:
			if !ok {
				break
			}
			wlog.Error(fmt.Sprintf("amqp connection receive error: %s", err.Error()))
			a.initConnection()
		case <-a.stop:
			wlog.Debug("listener call received stop signal")
			return
		}
	}
}

func (a *AMQP) initConnection() {
	var err error

	if a.connectionAttempts >= MAX_ATTEMPTS_CONNECT {
		wlog.Critical(fmt.Sprintf("Failed to open AMQP connection..."))
		time.Sleep(time.Second)
		os.Exit(1)
	}
	a.connectionAttempts++
	a.connection, err = amqp.Dial(a.settings.Url)
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
			a.initExchange()
			a.errorChan = make(chan *amqp.Error, 1)
			a.channel.NotifyClose(a.errorChan)
		}
	}
}

func (a *AMQP) initExchange() {
	err := a.channel.ExchangeDeclare(
		model.CallCenterExchange,
		"topic",
		true,
		false,
		false,
		true,
		nil,
	)
	if err != nil {
		wlog.Critical(fmt.Sprintf("Failed to declare AMQP exchange to err:%v", err.Error()))
		time.Sleep(time.Second)
		os.Exit(EXIT_DECLARE_EXCHANGE)
	}
}

func (a *AMQP) handleCallMessage(data []byte) {
	callAction := model.CallActionData{}
	if err := json.Unmarshal(data, &callAction); err != nil {
		wlog.Error(fmt.Sprintf("parse error: %s", err.Error()))
		return
	}
	wlog.Debug(fmt.Sprintf("call %s [%s] ", callAction.Id, callAction.Action))
	a.callEvent <- callAction
}

func (a *AMQP) Close() {
	wlog.Debug("AMQP receive stop client")
	close(a.stop)
	<-a.stopped

	if a.channel != nil {
		a.channel.Close()
		wlog.Debug("close AMQP channel")
	}

	if a.connection != nil {
		a.connection.Close()
		wlog.Debug("close AMQP connection")
	}
}

func (a *AMQP) SendJSON(key string, data []byte) *model.AppError {
	//todo, check connection
	err := a.channel.Publish(
		model.CallCenterExchange,
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

func (a *AMQP) ConsumeCallEvent() <-chan model.CallActionData {
	return a.callEvent
}

func getId(name string) string {
	return model.MQ_EVENT_PREFIX + "." + name
}
