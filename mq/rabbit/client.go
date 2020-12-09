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
	"strconv"
	"strings"
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
	delivery           <-chan amqp.Delivery
	queue              amqp.Queue
	nodeName           string
	connectionAttempts int
	callEvent          chan model.CallActionData
	chatEvent          chan model.ChatEvent
	queueEvent         mq.QueueEvent
}

func NewRabbitMQ(settings model.MessageQueueSettings, nodeName string) mq.LayeredMQLayer {
	mq_ := &AMQP{
		settings:  &settings,
		errorChan: make(chan *amqp.Error, 1),
		stop:      make(chan struct{}),
		stopped:   make(chan struct{}),
		callEvent: make(chan model.CallActionData),
		chatEvent: make(chan model.ChatEvent),
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
		case m := <-a.delivery:
			a.readMessage(&m)

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

func (a *AMQP) readMessage(msg *amqp.Delivery) {
	switch msg.Exchange {
	case model.CallExchange:
		var ev model.CallActionData
		err := json.Unmarshal(msg.Body, &ev)
		if err != nil {
			wlog.Error(fmt.Sprintf("%s :\n%s", err.Error(), string(msg.Body)))
			return
		}
		a.callEvent <- ev

	case model.ChatExchange:
		a.readChatEvent(msg.Body, msg.RoutingKey)

	default:
		wlog.Error(fmt.Sprintf("no handler for message %s", string(msg.Body)))

	}
}

func (a *AMQP) readChatEvent(data []byte, rk string) {
	rks := strings.Split(rk, ".")
	if len(rks) != 4 {
		wlog.Error(fmt.Sprintf("event %s: bad rk format", rk))
		return
	}

	domainId, err := strconv.Atoi(rks[2])
	if err != nil {
		wlog.Error(fmt.Sprintf("event %s: bad domainId", rk))
		return
	}

	userId, err := strconv.Atoi(rks[3])
	if err != nil {
		wlog.Error(fmt.Sprintf("event %s: bad userId", rk))
		return
	}

	var body map[string]interface{}

	if err = json.Unmarshal(data, &body); err != nil {
		wlog.Error(fmt.Sprintf("event %s: error json unmarshal %s", rk, err.Error()))
		return
	}

	a.chatEvent <- model.ChatEvent{
		Name:     rks[1],
		DomainId: int64(domainId),
		UserId:   int64(userId),

		Data: body,
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
			if err = a.connect(); err != nil {
				panic(err.Error())
			}
			a.errorChan = make(chan *amqp.Error, 1)
			a.channel.NotifyClose(a.errorChan)
		}
	}
}

func (a *AMQP) connect() error {
	var err error
	a.queue, err = a.channel.QueueDeclare(
		fmt.Sprintf("callcenter.%s", a.nodeName),
		false,
		false,
		true,
		false,
		nil,
	)

	if err != nil {
		return err
	}

	a.delivery, err = a.channel.Consume(
		a.queue.Name,
		model.NewId(),
		true,
		true,
		false,
		true,
		nil,
	)

	if err != nil {
		return err
	}

	//err = a.channel.QueueBind(a.queue.Name, "#", model.ChatExchange, true, nil)
	//if err != nil {
	//	return err
	//}

	return a.channel.QueueBind(a.queue.Name, fmt.Sprintf(model.CallRoutingTemplate, a.nodeName), model.CallExchange, true, nil)
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
	wlog.Debug(fmt.Sprintf("publish %s [%s]", key, string(data)))
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

func (a *AMQP) ConsumeChatEvent() <-chan model.ChatEvent {
	return a.chatEvent
}
