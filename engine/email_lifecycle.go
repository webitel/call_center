package engine

import (
	"context"
	"errors"
	"time"

	"github.com/webitel/wlog"

	"github.com/webitel/call_center/model"
)

type EmailLifecycleStore interface {
	EmailLifecycleWatch(ctx context.Context, batch int, maxDuration, lockTimeout, statementTimeout time.Duration) (*model.EmailLifecycleResult, *model.AppError)
}

type EmailLifecycleSettings struct {
	Interval         time.Duration
	Batch            int
	LockTimeout      time.Duration
	StatementTimeout time.Duration
}

func (s EmailLifecycleSettings) Validate() error {
	if s.Batch <= 0 {
		return errors.New("email lifecycle: batch must be positive")
	}
	return validateEmailCycle("email lifecycle", s.Interval, s.LockTimeout, s.StatementTimeout)
}

// EmailLifecycleWatcher applies due deadlines and returns Emails of offline agents on every node.
// Deadlines are kept in the database on its time, so a restart changes none of them.
type EmailLifecycleWatcher struct {
	store    EmailLifecycleStore
	settings EmailLifecycleSettings
	stop     chan struct{}
	stopped  chan struct{}
	log      *wlog.Logger
	emailWarner
}

func NewEmailLifecycleWatcher(s EmailLifecycleStore, settings EmailLifecycleSettings, log *wlog.Logger) *EmailLifecycleWatcher {
	return &EmailLifecycleWatcher{
		store:    s,
		settings: settings,
		log: log.With(
			wlog.Namespace("context"),
			wlog.String("name", "email_lifecycle"),
		),
	}
}

func (w *EmailLifecycleWatcher) Start() {
	w.log.Info("starting email lifecycle watcher",
		wlog.Duration("interval", w.settings.Interval),
		wlog.Int("batch", w.settings.Batch),
	)
	w.stop = make(chan struct{})
	w.stopped = make(chan struct{})
	go func() {
		defer close(w.stopped)
		runEmailCycles(w.stop, w.settings.Interval, w.Watch)
	}()
}

// Stop interrupts the pause and waits for a running cycle; transitions it committed stay.
func (w *EmailLifecycleWatcher) Stop() {
	if w.stop != nil {
		close(w.stop)
		<-w.stopped
	}
}

// Watch runs one cycle; false means it failed and was rolled back, so the next one backs off.
func (w *EmailLifecycleWatcher) Watch() bool {
	start := time.Now()
	ctx, cancel := context.WithTimeout(context.Background(), w.settings.StatementTimeout+time.Second)
	defer cancel()

	// Half of the statement timeout leaves the cycle time to return and commit.
	res, err := w.store.EmailLifecycleWatch(ctx, w.settings.Batch, w.settings.StatementTimeout/2,
		w.settings.LockTimeout, w.settings.StatementTimeout)
	latency := time.Since(start)
	if err != nil {
		outcome := model.EmailLifecycleOutcome(err)
		if w.shouldWarn("cycle_error:"+outcome, time.Now()) {
			w.log.Error("email lifecycle cycle failed and was rolled back", wlog.Err(err),
				wlog.String("outcome", outcome), wlog.Duration("latency", latency))
		}
		return false
	}

	if res.TimeLimited && w.shouldWarn("time_limit", time.Now()) {
		w.log.Warn("email lifecycle cycle reached its time limit; the rest waits for the next cycle",
			wlog.Duration("latency", latency))
	}

	fields := []wlog.Field{
		wlog.Int("released", res.Released),
		wlog.Int("processing_timeouts", res.ProcessingTimeouts),
		wlog.Int("postponed_woken", res.PostponedWoken),
		wlog.Int("postponed_queued", res.PostponedQueued),
		wlog.Int("offline_returned", res.OfflineReturned),
		wlog.Int("lock_skipped", res.LockSkipped),
		wlog.Duration("latency", latency),
	}
	if res.Released+res.ProcessingTimeouts+res.PostponedWoken+res.PostponedQueued+res.OfflineReturned > 0 {
		w.log.Info("email lifecycle cycle", fields...)
	} else {
		w.log.Debug("email lifecycle cycle", fields...)
	}
	return true
}
