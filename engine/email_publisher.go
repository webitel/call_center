package engine

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/webitel/wlog"

	"github.com/webitel/call_center/model"
)

const (
	// emailPublishRetryPause delays the rows given back after a failure, so other nodes do not retry them at once.
	emailPublishRetryPause  = 5 * time.Second
	emailOutboxCleanupEvery = time.Minute
	emailOutboxCleanupBatch = 1000
	emailOutboxStoreTimeout = 10 * time.Second
)

type EmailOutboxStore interface {
	EmailOutboxClaim(ctx context.Context, owner string, batch int, lease time.Duration) ([]*model.EmailOutboxRow, *model.AppError)
	EmailOutboxPublished(ctx context.Context, owner string, sequences []int64) (int64, *model.AppError)
	EmailOutboxRelease(ctx context.Context, owner string, sequences []int64, next time.Time, reason string, failed bool) *model.AppError
	EmailOutboxCleanup(ctx context.Context, before time.Time, limit int) (int64, *model.AppError)
	EmailOutboxBacklog(ctx context.Context) (*model.EmailOutboxBacklog, *model.AppError)
}

type EmailSnapshotBroker interface {
	Declare(ctx context.Context) error
	Publish(ctx context.Context, eventId string, body []byte) error
	Close()
}

type EmailPublisherSettings struct {
	Interval       time.Duration
	Batch          int
	Lease          time.Duration
	ConfirmTimeout time.Duration
	Retention      time.Duration
}

func (s EmailPublisherSettings) Validate() error {
	if s.Batch <= 0 {
		return errors.New("email publisher: batch must be positive")
	}
	if s.Interval < time.Millisecond || s.Lease < time.Millisecond || s.ConfirmTimeout < time.Millisecond || s.Retention < time.Millisecond {
		return errors.New("email publisher: interval, lease, confirm timeout and retention must be at least 1ms")
	}
	if s.Lease <= s.ConfirmTimeout {
		return errors.New("email publisher: lease must be longer than confirm timeout")
	}
	return nil
}

// EmailPublisher sends cc_email_attempt_outbox rows to email-service on every node. Rows are leased in
// the database, so nodes never publish the same row at once; a row may still be sent twice after a failure.
type EmailPublisher struct {
	store       EmailOutboxStore
	broker      EmailSnapshotBroker
	settings    EmailPublisherSettings
	owner       string
	declared    bool
	lastCleanup time.Time
	stop        chan struct{}
	stopped     chan struct{}
	log         *wlog.Logger
	emailWarner
}

func NewEmailPublisher(s EmailOutboxStore, broker EmailSnapshotBroker, settings EmailPublisherSettings, owner string, log *wlog.Logger) *EmailPublisher {
	return &EmailPublisher{
		store:    s,
		broker:   broker,
		settings: settings,
		owner:    owner,
		log: log.With(
			wlog.Namespace("context"),
			wlog.String("name", "email_publisher"),
		),
	}
}

func (p *EmailPublisher) Start() {
	p.log.Info("starting email snapshot publisher",
		wlog.Duration("interval", p.settings.Interval),
		wlog.Int("batch", p.settings.Batch),
	)
	p.stop = make(chan struct{})
	p.stopped = make(chan struct{})
	go func() {
		defer close(p.stopped)
		runEmailCycles(p.stop, p.settings.Interval, p.Publish)
	}()
}

// Stop interrupts the pause and waits for a running cycle; leased rows it did not publish return after the lease.
func (p *EmailPublisher) Stop() {
	if p.stop != nil {
		close(p.stop)
		<-p.stopped
	}
	p.broker.Close()
}

// Publish runs one cycle; false means the broker or the database failed, so the next one backs off.
func (p *EmailPublisher) Publish() bool {
	start := time.Now()
	p.cleanup(start)

	if !p.declared {
		ctx, cancel := context.WithTimeout(context.Background(), p.settings.ConfirmTimeout)
		err := p.broker.Declare(ctx)
		cancel()
		if err != nil {
			p.warn("declare", "email snapshot exchange declaration failed", err)
			return false
		}
		p.declared = true
	}

	ctx, cancel := context.WithTimeout(context.Background(), emailOutboxStoreTimeout)
	rows, appErr := p.store.EmailOutboxClaim(ctx, p.owner, p.settings.Batch, p.settings.Lease)
	cancel()
	if appErr != nil {
		p.warn("claim", "email outbox claim failed", appErr)
		return false
	}
	if len(rows) == 0 {
		return true
	}

	// Rows not published before the lease could end go back instead of being sent by two nodes.
	deadline := start.Add(p.settings.Lease - p.settings.ConfirmTimeout)
	published := make([]int64, 0, len(rows))
	var failure error
	for i, row := range rows {
		if time.Now().After(deadline) {
			p.release(rows[i:], time.Now(), "lease ends before publish", false)
			break
		}

		body, err := json.Marshal(row.Event())
		if err != nil {
			p.release(rows[i:i+1], time.Now().Add(emailPublishRetryPause), err.Error(), true)
			p.warn("encode", "email snapshot cannot be encoded", err, wlog.Int64("sequence", row.Sequence))
			continue
		}

		pctx, pcancel := context.WithTimeout(context.Background(), p.settings.ConfirmTimeout)
		err = p.broker.Publish(pctx, model.EmailSnapshotEventId(row.Sequence), body)
		pcancel()
		if err != nil {
			// A broker or topology failure is not the fault of the row: no attempt is spent.
			failure = err
			p.release(rows[i:], time.Now().Add(emailPublishRetryPause), err.Error(), false)
			break
		}
		published = append(published, row.Sequence)
	}

	// published holds what the broker confirmed; marked is what the database recorded.
	var marked int64
	if len(published) > 0 {
		ctx, cancel = context.WithTimeout(context.Background(), emailOutboxStoreTimeout)
		marked, appErr = p.store.EmailOutboxPublished(ctx, p.owner, published)
		cancel()
	}

	fields := []wlog.Field{
		wlog.Int("claimed", len(rows)),
		wlog.Int("confirmed", len(published)),
		wlog.Int64("published", marked),
		wlog.Duration("latency", time.Since(start)),
	}
	if marked < int64(len(published)) {
		// The rows are sent again after the lease; email-service ignores the repeated snapshots.
		if appErr == nil {
			appErr = model.NewAppError("EmailPublisher.Publish", "engine.email_publisher.lease_lost", nil,
				"another publisher holds some of the confirmed rows", http.StatusConflict)
		}
		p.warn("mark", "email outbox rows were confirmed but not marked published", appErr, fields...)
		if failure == nil {
			return false
		}
	}
	if failure != nil {
		p.declared = false
		p.broker.Close()
		p.warn("broker", "email snapshot publish failed; the rest of the batch is retried", failure, fields...)
		return false
	}
	if marked > 0 {
		p.log.Info("email publisher cycle", fields...)
	} else {
		p.log.Debug("email publisher cycle", fields...)
	}
	return true
}

func (p *EmailPublisher) release(rows []*model.EmailOutboxRow, next time.Time, reason string, failed bool) {
	sequences := make([]int64, 0, len(rows))
	for _, r := range rows {
		sequences = append(sequences, r.Sequence)
	}
	ctx, cancel := context.WithTimeout(context.Background(), emailOutboxStoreTimeout)
	defer cancel()
	if err := p.store.EmailOutboxRelease(ctx, p.owner, sequences, next, reason, failed); err != nil {
		// The lease returns them anyway.
		p.warn("release", "email outbox rows were not given back", err)
	}
}

// cleanup deletes old published rows and reports the backlog once a minute.
func (p *EmailPublisher) cleanup(now time.Time) {
	if now.Sub(p.lastCleanup) < emailOutboxCleanupEvery {
		return
	}
	p.lastCleanup = now

	ctx, cancel := context.WithTimeout(context.Background(), emailOutboxStoreTimeout)
	defer cancel()
	deleted, err := p.store.EmailOutboxCleanup(ctx, now.Add(-p.settings.Retention), emailOutboxCleanupBatch)
	if err != nil {
		p.warn("cleanup", "email outbox cleanup failed", err)
	}
	backlog, err := p.store.EmailOutboxBacklog(ctx)
	if err != nil {
		p.warn("backlog", "email outbox backlog is unknown", err)
		return
	}

	fields := []wlog.Field{wlog.Int64("deleted", deleted), wlog.Int64("backlog", backlog.Pending)}
	if backlog.OldestAt != nil {
		fields = append(fields, wlog.Duration("oldest_pending_age", now.Sub(*backlog.OldestAt)))
	}
	if deleted > 0 || backlog.Pending > 0 {
		p.log.Info("email outbox", fields...)
	} else {
		p.log.Debug("email outbox", fields...)
	}
}

func (p *EmailPublisher) warn(key, msg string, err error, fields ...wlog.Field) {
	if p.shouldWarn(key, time.Now()) {
		p.log.Warn(msg, append(fields, wlog.Err(err))...)
	}
}
