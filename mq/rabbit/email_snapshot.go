package rabbit

import (
	"context"
	"errors"
	"fmt"
	"net"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"

	"github.com/webitel/call_center/model"
)

var (
	errEmailSnapshotNack       = errors.New("email snapshot: broker refused the message")
	errEmailSnapshotUnroutable = errors.New("email snapshot: no queue is bound to the routing key")
)

// EmailSnapshotPublisher sends Email attempt snapshots over its own connection and confirmed channel,
// apart from the shared AMQP client. It is not safe for concurrent use; the connection opens lazily.
type EmailSnapshotPublisher struct {
	url     string
	timeout time.Duration
	conn    *amqp.Connection
	ch      *amqp.Channel
	returns chan amqp.Return
}

// NewEmailSnapshotPublisher bounds connecting and every network write by timeout; a context
// cannot stop a write that has started.
func NewEmailSnapshotPublisher(url string, timeout time.Duration) *EmailSnapshotPublisher {
	return &EmailSnapshotPublisher{url: url, timeout: timeout}
}

// Declare opens the channel when needed and declares the exchange of the snapshots.
func (p *EmailSnapshotPublisher) Declare(ctx context.Context) error {
	if err := p.open(); err != nil {
		return err
	}
	if err := p.ch.ExchangeDeclare(model.EmailSnapshotExchange, "topic", true, false, false, false, nil); err != nil {
		p.Close()
		return fmt.Errorf("email snapshot: declare %s: %w", model.EmailSnapshotExchange, err)
	}

	return ctx.Err()
}

// Publish succeeds only when the broker confirmed the persistent message and routed it to a queue.
func (p *EmailSnapshotPublisher) Publish(ctx context.Context, eventId string, body []byte) error {
	if err := p.open(); err != nil {
		return err
	}
	// A return of an earlier timed out message must not fail this one.
	for len(p.returns) > 0 {
		<-p.returns
	}

	dc, err := p.ch.PublishWithDeferredConfirmWithContext(ctx, model.EmailSnapshotExchange, model.EmailSnapshotRoutingKey,
		true, false, amqp.Publishing{
			ContentType:  model.EmailSnapshotContentType,
			DeliveryMode: amqp.Persistent,
			MessageId:    eventId,
			Headers: amqp.Table{
				model.EmailSnapshotHeaderEventId:       eventId,
				model.EmailSnapshotHeaderEventType:     model.EmailSnapshotEventType,
				model.EmailSnapshotHeaderSchemaVersion: model.EmailSnapshotSchema,
			},
			Body: body,
		})
	if err != nil {
		p.Close()
		return fmt.Errorf("email snapshot: publish: %w", err)
	}

	acked, err := dc.WaitContext(ctx)
	if err != nil {
		// The result is unknown; a new channel keeps a late confirm from being taken for another message.
		p.Close()
		return fmt.Errorf("email snapshot: confirm: %w", err)
	}
	if !acked {
		return errEmailSnapshotNack
	}
	// A mandatory message without a queue is returned before its ack.
	select {
	case r := <-p.returns:
		if r.MessageId == eventId {
			return errEmailSnapshotUnroutable
		}
	default:
	}

	return nil
}

// Close drops the connection; the next call opens a new one.
func (p *EmailSnapshotPublisher) Close() {
	if p.ch != nil {
		_ = p.ch.Close()
	}
	if p.conn != nil {
		_ = p.conn.Close()
	}
	p.conn, p.ch, p.returns = nil, nil, nil
}

func (p *EmailSnapshotPublisher) open() error {
	if p.ch != nil && !p.ch.IsClosed() && !p.conn.IsClosed() {
		return nil
	}
	p.Close()

	conn, err := amqp.DialConfig(p.url, amqp.Config{Locale: "en_US", Dial: p.dial})
	if err != nil {
		return fmt.Errorf("email snapshot: connect: %w", err)
	}
	ch, err := conn.Channel()
	if err == nil {
		err = ch.Confirm(false)
	}
	if err != nil {
		_ = conn.Close()
		return fmt.Errorf("email snapshot: open channel: %w", err)
	}

	p.conn, p.ch = conn, ch
	p.returns = ch.NotifyReturn(make(chan amqp.Return, 1))
	return nil
}

// dial bounds the TCP connect and the AMQP handshake like amqp.DefaultDial; amqp091 clears that
// deadline after the handshake, and every later write gets its own.
func (p *EmailSnapshotPublisher) dial(network, addr string) (net.Conn, error) {
	conn, err := net.DialTimeout(network, addr, p.timeout)
	if err != nil {
		return nil, err
	}
	if err = conn.SetDeadline(time.Now().Add(p.timeout)); err != nil {
		_ = conn.Close()
		return nil, err
	}

	return &emailWriteDeadlineConn{Conn: conn, timeout: p.timeout}, nil
}

// emailWriteDeadlineConn fails a write blocked by a broker that stopped reading.
type emailWriteDeadlineConn struct {
	net.Conn
	timeout time.Duration
}

func (c *emailWriteDeadlineConn) Write(b []byte) (int, error) {
	if err := c.Conn.SetWriteDeadline(time.Now().Add(c.timeout)); err != nil {
		return 0, err
	}

	return c.Conn.Write(b)
}
