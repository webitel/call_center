package rabbit

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync/atomic"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"

	"github.com/webitel/wlog"

	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
)

const (
	MAX_ATTEMPTS_CONNECT = 100
	RECONNECT_SEC        = 5
)

const (
	EXIT_DECLARE_EXCHANGE = 110
)

var (
	errConnectionClosed = errors.New("amqp: connection is closed")
	errChannelClosed    = errors.New("amqp: channel is closed")
)

type AMQP struct {
	settings           *model.MessageQueueSettings
	connection         atomic.Pointer[amqp.Connection]
	channel            atomic.Pointer[amqp.Channel]
	errorChan          chan *amqp.Error
	stop               chan struct{}
	stopped            chan struct{}
	delivery           <-chan amqp.Delivery
	queue              amqp.Queue
	nodeName           string
	connectionAttempts int
	callEvent          chan model.CallActionData
	chatEvent          chan model.ChatEvent
	imEvent            chan model.IMMessage
	queueEvent         mq.QueueEvent
	log                *wlog.Logger
}

type BotGrantedMessageAgent struct {
	MemberId string `json:"member_id"`
}
type BotGrantedMessage struct {
	ThreadId     string                   `json:"thread_id"`
	DomainId     int64                    `json:"domain_id"`
	MemberId     string                   `json:"member_id"`
	Position     int                      `json:"position"`
	Reason       string                   `json:"reason"`
	NextMemberId string                   `json:"next_member_id"`
	Sub          *int64                   `json:"sub"`
	Agents       []BotGrantedMessageAgent `json:"agents"`
	OccurredAt   string                   `json:"occurred_at"`
}

type BotReleasedMessage struct {
	ThreadId string `json:"thread_id"`
	DomainId int64  `json:"domain_id"`
	MemberId string `json:"member_id"`
	Reason   string `json:"reason"`
}

func NewRabbitMQ(settings model.MessageQueueSettings, nodeName string, log *wlog.Logger) mq.LayeredMQLayer {
	mq_ := &AMQP{
		settings:  &settings,
		errorChan: make(chan *amqp.Error, 1),
		stop:      make(chan struct{}),
		stopped:   make(chan struct{}),
		callEvent: make(chan model.CallActionData, 100),
		chatEvent: make(chan model.ChatEvent, 100),
		imEvent:   make(chan model.IMMessage, 100),
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

func (a *AMQP) Ping(context.Context) error {
	conn := a.connection.Load()
	if conn == nil || conn.IsClosed() {
		return errConnectionClosed
	}

	ch := a.channel.Load()
	if ch == nil || ch.IsClosed() {
		return errChannelClosed
	}

	return nil
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
	// fmt.Println(string(msg.Body))
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

	var body map[string]any

	if err = json.Unmarshal(data, &body); err != nil {
		log.Error(fmt.Sprintf("event %s: error json unmarshal %s", rk, err.Error()),
			wlog.Err(err),
		)
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
		a.log.Critical(fmt.Sprintf("Failed to open AMQP connection..."))
		time.Sleep(time.Second)
		os.Exit(1)
	}
	a.connectionAttempts++
	var conn *amqp.Connection
	conn, err = amqp.Dial(a.settings.Url)
	a.connection.Store(conn)
	if err != nil {
		a.log.Critical(fmt.Sprintf("Failed to open AMQP connection to err:%v", err.Error()))
		time.Sleep(time.Second * RECONNECT_SEC)
		a.initConnection()
	} else {
		a.connectionAttempts = 0
		var ch *amqp.Channel
		ch, err = conn.Channel()
		a.channel.Store(ch)

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
			ch.NotifyClose(a.errorChan)
			if a.settings.UseIM {
				a.subscribeIM()
			}
		}
	}
}

func (a *AMQP) connect() error {
	var err error
	ch := a.channel.Load()
	a.queue, err = ch.QueueDeclare(
		fmt.Sprintf("callcenter.%s", a.nodeName),
		true,
		false,
		false,
		false,
		amqp.Table{
			"x-queue-type": "quorum",
			"x-expires":    10000, // delete after 10s
		},
	)
	if err != nil {
		return err
	}

	a.delivery, err = ch.Consume(
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

	err = ch.QueueBind(a.queue.Name, "#", model.ChatExchange, true, nil)
	if err != nil {
		return err
	}

	return ch.QueueBind(a.queue.Name, fmt.Sprintf(model.CallRoutingTemplate, a.nodeName), model.CallExchange, true, nil)
}

func (a *AMQP) initExchange() {
	err := a.channel.Load().ExchangeDeclare(
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

func (a *AMQP) subscribeIM() {
	imQueueName := fmt.Sprintf("%s.%s.any", model.IMQueueNamePrefix, model.NewId()[0:8])

	ch := a.channel.Load()

	imQueue, err := ch.QueueDeclare(
		imQueueName,
		true,
		false,
		false,
		true,
		amqp.Table{
			"x-queue-type": "quorum",
			"x-expires":    10000, // delete after 10s
		},
	)
	if err != nil {
		wlog.Critical(fmt.Sprintf("Failed to declare AMQP queue %v to err:%v", imQueueName, err.Error()))
		time.Sleep(time.Second)
		os.Exit(1)
	} else {
		wlog.Debug(fmt.Sprintf("Success declare queue %v connected consumers %v", imQueue.Name, imQueue.Consumers))
	}

	if err = ch.QueueBind(imQueue.Name, "#", model.IMExchange, true, nil); err != nil {
		wlog.Critical(fmt.Sprintf("Error binding queue %s to %s: %s", imQueue.Name, model.IMExchange, err.Error()))
		time.Sleep(time.Second)
		os.Exit(1)
	}

	msgs, err := ch.Consume(
		imQueue.Name,
		"",
		false,
		false,
		false,
		false,
		nil,
	)
	if err != nil {
		wlog.Critical(fmt.Sprintf("Error create consume for queue %s: %s", imQueue.Name, err.Error()))
		time.Sleep(time.Second)
		os.Exit(1)
	}

	if err = ch.QueueBind(imQueue.Name, "im_thread.*.bot.control.#", "im_message.events", true, nil); err != nil {
		wlog.Critical("[AMQP] during binding IM queue to message exchange", wlog.String("queue", imQueue.Name), wlog.String("exchange", model.IMExchange), wlog.Err(err))
		panic("error during binding IM queue to message exchange")
	}

	go func() {
		for m := range msgs {
			switch m.Exchange {
			case model.IMExchange:
				var data model.IMMessageWrapper
				json.Unmarshal(m.Body, &data)
				println(string(m.Body))
				if data.Echo {
					println("skip echo")
					continue
				}
				a.imEvent <- data.Message

			case "im_message.events":

				switch {
				case strings.HasPrefix(m.RoutingKey, "im_thread.") && strings.HasSuffix(m.RoutingKey, ".bot.control.granted.v1"):
					var grm BotGrantedMessage
					if err := json.Unmarshal(m.Body, &grm); err != nil {
						wlog.Warn(fmt.Sprintf("unable to parse bot control granted event: %s", err.Error()))

						break
					}

					if grm.Reason == "transfer" && len(grm.Agents) != 0 {
						a.imEvent <- model.IMMessage{
							ThreadID: grm.ThreadId,
							DomainID: int(grm.DomainId),
							System: &model.IMSystem{
								Type: grm.Reason,
								Metadata: model.IMSystemMetadata{
									TransferredMemberId: grm.Agents[0].MemberId,
								},
							},
						}

						break
					}

					a.imEvent <- model.IMMessage{
						ThreadID: grm.ThreadId,
						DomainID: int(grm.DomainId),
						System:   &model.IMSystem{Type: model.IMSystemTypeBotControlGranted},
					}

				case strings.HasPrefix(m.RoutingKey, "im_thread.") && strings.HasSuffix(m.RoutingKey, ".bot.control.released.v1"):
					var rel BotReleasedMessage
					if err := json.Unmarshal(m.Body, &rel); err != nil {
						wlog.Warn(fmt.Sprintf("unable to parse bot control released event: %s", err.Error()))

						break
					}

					a.imEvent <- model.IMMessage{
						ThreadID: rel.ThreadId,
						DomainID: int(rel.DomainId),
						System:   &model.IMSystem{Type: model.IMSystemTypeBotControlReleased},
					}
				}

			default:
				wlog.Warn(fmt.Sprintf("unable to parse event, not found exchange %s", m.Exchange))
			}

			m.Ack(false)
		}
	}()
}

func (a *AMQP) Close() {
	a.log.Debug("AMQP receive stop client")
	close(a.stop)
	<-a.stopped

	if ch := a.channel.Load(); ch != nil {
		ch.Close()
		a.log.Debug("close AMQP channel")
	}

	if conn := a.connection.Load(); conn != nil {
		conn.Close()
		a.log.Debug("close AMQP connection")
	}
}

func (a *AMQP) SendJSON(key string, data []byte) *model.AppError {
	// todo, check connection
	a.log.Debug(fmt.Sprintf("publish %s [%s]", key, string(data)),
		wlog.String("routing", key),
		wlog.String("exchange", model.CallCenterExchange),
	)
	err := a.channel.Load().Publish(
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

func (a *AMQP) ConsumeIMEvent() <-chan model.IMMessage {
	return a.imEvent
}
