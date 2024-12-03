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
	log                *wlog.Logger
}

func NewRabbitMQ(settings model.MessageQueueSettings, nodeName string, log *wlog.Logger) mq.LayeredMQLayer {
	mq_ := &AMQP{
		settings:  &settings,
		errorChan: make(chan *amqp.Error, 1),
		stop:      make(chan struct{}),
		stopped:   make(chan struct{}),
		callEvent: make(chan model.CallActionData, 100),
		chatEvent: make(chan model.ChatEvent),
		nodeName:  nodeName,
		log: log.With(
			wlog.Namespace("context"),
			wlog.String("protocol", "amqp"),
			wlog.String("name", "rabbit"),
		),
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
		a.log.Info("close amqp listener")
		close(a.stopped)
	}()
	a.log.Info("start amqp listener")

	for {
		select {
		case m := <-a.delivery:
			a.readMessage(&m)

		case err, ok := <-a.errorChan:
			if !ok {
				break
			}
			a.log.Error(fmt.Sprintf("amqp connection receive error: %s", err.Error()),
				wlog.Err(err),
			)
			a.initConnection()
		case <-a.stop:
			a.log.Debug("listener call received stop signal")
			return
		}
	}
}

func (a *AMQP) readMessage(msg *amqp.Delivery) {
	//fmt.Println(string(msg.Body))
	log := a.log.With(
		wlog.String("exchange", msg.Exchange),
		wlog.String("routing", msg.RoutingKey),
	)
	switch msg.Exchange {
	case model.CallExchange:
		var ev model.CallActionData
		err := json.Unmarshal(msg.Body, &ev)
		if err != nil {
			log.Error(fmt.Sprintf("%s :\n%s", err.Error(), string(msg.Body)),
				wlog.Err(err),
			)
			return
		}
		if ev.Event == "heartbeat" {
			return // TODO
		}
		a.callEvent <- ev

	case model.ChatExchange:
		a.readChatEvent(msg.Body, msg.RoutingKey, log)

	default:
		log.Error(fmt.Sprintf("no handler for message %s", string(msg.Body)))

	}
}

func (a *AMQP) readChatEvent(data []byte, rk string, log *wlog.Logger) {
	rks := strings.Split(rk, ".")
	if len(rks) != 4 {
		log.Error(fmt.Sprintf("event %s: bad rk format", rk))
		return
	}

	domainId, err := strconv.Atoi(rks[2])
	if err != nil {
		log.Error(fmt.Sprintf("event %s: bad domainId", rk),
			wlog.Err(err),
		)
		return
	}

	userId, err := strconv.Atoi(rks[3])
	if err != nil {
		log.Error(fmt.Sprintf("event %s: bad userId", rk),
			wlog.Err(err),
		)
		return
	}

	var body map[string]interface{}

	if err = json.Unmarshal(data, &body); err != nil {
		log.Error(fmt.Sprintf("event %s: error json unmarshal %s", rk, err.Error()),
			wlog.Err(err),
		)
		return
	}

	//fmt.Println(string(data))

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
		a.log.Critical(fmt.Sprintf("Failed to open AMQP connection..."))
		time.Sleep(time.Second)
		os.Exit(1)
	}
	a.connectionAttempts++
	a.connection, err = amqp.Dial(a.settings.Url)
	if err != nil {
		a.log.Critical(fmt.Sprintf("Failed to open AMQP connection to err:%v", err.Error()))
		time.Sleep(time.Second * RECONNECT_SEC)
		a.initConnection()
	} else {
		a.connectionAttempts = 0
		a.channel, err = a.connection.Channel()

		if err != nil {
			a.log.Critical(fmt.Sprintf("Failed to open AMQP channel to err:%v", err.Error()))
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
		false,
		nil,
	)

	if err != nil {
		return err
	}

	err = a.channel.QueueBind(a.queue.Name, "#", model.ChatExchange, true, nil)
	if err != nil {
		return err
	}

	return a.channel.QueueBind(a.queue.Name, fmt.Sprintf(model.CallRoutingTemplate, a.nodeName), model.CallExchange, true, nil)
}

func (a *AMQP) initExchange() {
	err := a.channel.ExchangeDeclare(
		model.CallCenterExchange,
		"topic",
		true,
		false,
		false,
		false,
		nil,
	)
	if err != nil {
		a.log.Critical(fmt.Sprintf("Failed to declare AMQP exchange to err:%v", err.Error()),
			wlog.Err(err),
		)
		time.Sleep(time.Second)
		os.Exit(EXIT_DECLARE_EXCHANGE)
	}
}

func (a *AMQP) Close() {
	a.log.Debug("AMQP receive stop client")
	close(a.stop)
	<-a.stopped

	if a.channel != nil {
		a.channel.Close()
		a.log.Debug("close AMQP channel")
	}

	if a.connection != nil {
		a.connection.Close()
		a.log.Debug("close AMQP connection")
	}
}

func (a *AMQP) SendJSON(key string, data []byte) *model.AppError {
	//todo, check connection
	a.log.Debug(fmt.Sprintf("publish %s [%s]", key, string(data)),
		wlog.String("routing", key),
		wlog.String("exchange", model.CallCenterExchange),
	)
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
