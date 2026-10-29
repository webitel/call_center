package engine

import (
	"context"
	"errors"
	"fmt"
	"math/rand"
	"sync"
	"time"

	"github.com/webitel/wlog"

	"github.com/webitel/call_center/model"
)

// emailWarnEvery limits repeated warnings about one misconfigured queue or failing cycles.
const emailWarnEvery = 5 * time.Minute

// emailMaxBackoff caps the pause after failed cycles, which doubles from twice the polling interval.
const emailMaxBackoff = time.Minute

type EmailDistributeStore interface {
	EmailDistribute(ctx context.Context, queueBatch int, maxDuration, lockTimeout, statementTimeout time.Duration) ([]*model.EmailDistributeResult, *model.AppError)
}

type EmailDistributorSettings struct {
	Interval         time.Duration
	QueueBatch       int
	LockTimeout      time.Duration
	StatementTimeout time.Duration
}

// Validate keeps whole milliseconds: the store passes them to PostgreSQL, where 0 disables a timeout.
func (s EmailDistributorSettings) Validate() error {
	if s.QueueBatch <= 0 {
		return errors.New("email distribution: queue batch must be positive")
	}
	if s.Interval < time.Millisecond || s.LockTimeout < time.Millisecond || s.StatementTimeout < time.Millisecond {
		return errors.New("email distribution: interval and timeouts must be at least 1ms")
	}
	if s.LockTimeout >= s.StatementTimeout {
		return errors.New("email distribution: lock timeout must be less than statement timeout")
	}
	return nil
}

// EmailDistributor polls database-backed Email cycles on every node.
// The database serializes cycles, so it keeps no local attempt state.
type EmailDistributor struct {
	store    EmailDistributeStore
	settings EmailDistributorSettings
	stop     chan struct{}
	stopped  chan struct{}
	log      *wlog.Logger

	mu     sync.Mutex
	warned map[string]time.Time
}

func NewEmailDistributor(s EmailDistributeStore, settings EmailDistributorSettings, log *wlog.Logger) *EmailDistributor {
	return &EmailDistributor{
		store:    s,
		settings: settings,
		warned:   make(map[string]time.Time),
		log: log.With(
			wlog.Namespace("context"),
			wlog.String("name", "email_distributor"),
		),
	}
}

func (d *EmailDistributor) Start() {
	d.log.Info("starting email distribution",
		wlog.Duration("interval", d.settings.Interval),
		wlog.Int("queue_batch", d.settings.QueueBatch),
		wlog.Duration("max_duration", d.settings.StatementTimeout/2),
		wlog.Duration("lock_timeout", d.settings.LockTimeout),
		wlog.Duration("statement_timeout", d.settings.StatementTimeout),
	)
	d.stop = make(chan struct{})
	d.stopped = make(chan struct{})
	go d.run()
}

// Stop interrupts the pause and waits for a running cycle; assignments it committed stay.
func (d *EmailDistributor) Stop() {
	if d.stop != nil {
		close(d.stop)
		<-d.stopped
	}
}

// run keeps its own loop instead of utils.Watcher to back off after failed cycles only.
func (d *EmailDistributor) run() {
	defer close(d.stopped)
	var backoff time.Duration
	delay := d.settings.Interval
	for {
		t := time.NewTimer(delay)
		select {
		case <-d.stop:
			t.Stop()
			return
		case <-t.C:
		}

		if d.Distribute() {
			backoff, delay = 0, d.settings.Interval
			continue
		}
		// Up to 10% less at random, so the nodes do not retry together; never below the interval.
		backoff = nextEmailBackoff(backoff, d.settings.Interval)
		delay = max(backoff-time.Duration(rand.Int63n(int64(backoff)/10+1)), d.settings.Interval)
	}
}

func nextEmailBackoff(prev, interval time.Duration) time.Duration {
	if prev == 0 {
		prev = interval
	}
	return min(2*prev, max(emailMaxBackoff, interval))
}

// EmailCycle summarizes assignments and queue outcomes of one cycle.
type EmailCycle struct {
	Busy            bool
	TimeLimited     bool
	Assigned        int
	NoAgentQueues   int
	ClosedQueues    int
	NoSkillsQueues  []int32
	InvalidCalendar []int32
}

func SummarizeEmailCycle(rows []*model.EmailDistributeResult) EmailCycle {
	var c EmailCycle
	noAgentQueues := make(map[int32]struct{})
	for _, r := range rows {
		switch r.Result {
		case model.EmailDistributeBusy:
			c.Busy = true
		case model.EmailDistributeTimeLimit:
			c.TimeLimited = true
		case model.EmailDistributeAssigned:
			c.Assigned++
		case model.EmailDistributeNoAgent:
			if r.QueueId != nil && *r.QueueId > 0 {
				noAgentQueues[*r.QueueId] = struct{}{}
			}
		case model.EmailDistributeCalendarClosed:
			c.ClosedQueues++
		case model.EmailDistributeNoSkills:
			c.NoSkillsQueues = append(c.NoSkillsQueues, queueOf(r))
		case model.EmailDistributeCalendarInvalid:
			c.InvalidCalendar = append(c.InvalidCalendar, queueOf(r))
		}
	}
	c.NoAgentQueues = len(noAgentQueues)
	return c
}

// Distribute runs one cycle; false means it failed and was rolled back, so the next one backs off.
// A busy lock and the time limit of the cycle are not failures.
func (d *EmailDistributor) Distribute() bool {
	start := time.Now()
	ctx, cancel := context.WithTimeout(context.Background(), d.settings.StatementTimeout+time.Second)
	defer cancel()

	// Half of the statement timeout leaves the cycle time to return and commit.
	rows, err := d.store.EmailDistribute(ctx, d.settings.QueueBatch, d.settings.StatementTimeout/2,
		d.settings.LockTimeout, d.settings.StatementTimeout)
	latency := time.Since(start)
	if err != nil {
		outcome := model.EmailDistributeOutcome(err)
		if d.shouldWarn("cycle_error:"+outcome, time.Now()) {
			d.log.Error("email distribution cycle failed and was rolled back", wlog.Err(err),
				wlog.String("outcome", outcome), wlog.Duration("latency", latency))
		}
		return false
	}

	c := SummarizeEmailCycle(rows)
	now := time.Now()
	for _, q := range c.NoSkillsQueues {
		if d.shouldWarn(fmt.Sprintf("no_skills:%d", q), now) {
			d.log.Warn("inbound email queue has no enabled skills; its emails wait", wlog.Int("queue_id", int(q)))
		}
	}
	for _, q := range c.InvalidCalendar {
		if d.shouldWarn(fmt.Sprintf("calendar_invalid:%d", q), now) {
			d.log.Warn("inbound email queue has a missing or invalid calendar; its emails wait", wlog.Int("queue_id", int(q)))
		}
	}

	if c.TimeLimited && d.shouldWarn("time_limit", now) {
		d.log.Warn("email distribution cycle reached its time limit; the rest waits for the next cycle",
			wlog.Duration("latency", latency))
	}

	fields := []wlog.Field{
		wlog.Any("lock_skipped", c.Busy),
		wlog.Int("assigned", c.Assigned),
		wlog.Int("no_agent_queues", c.NoAgentQueues),
		wlog.Int("calendar_closed_queues", c.ClosedQueues),
		wlog.Int("config_error_queues", len(c.NoSkillsQueues)+len(c.InvalidCalendar)),
		wlog.Duration("latency", latency),
	}
	if c.Assigned > 0 {
		d.log.Info("email distribution cycle", fields...)
	} else {
		d.log.Debug("email distribution cycle", fields...)
	}
	return true
}

func (d *EmailDistributor) shouldWarn(key string, now time.Time) bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	if last, ok := d.warned[key]; ok && now.Sub(last) < emailWarnEvery {
		return false
	}
	d.warned[key] = now
	return true
}

func queueOf(r *model.EmailDistributeResult) int32 {
	if r.QueueId == nil {
		return 0
	}
	return *r.QueueId
}
