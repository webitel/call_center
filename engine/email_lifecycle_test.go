package engine

import (
	"context"
	"testing"
	"time"

	"github.com/webitel/wlog"

	"github.com/webitel/call_center/model"
)

type fakeLifecycleStore struct {
	err         *model.AppError
	maxDuration time.Duration
}

func (s *fakeLifecycleStore) EmailLifecycleWatch(_ context.Context, _ int, maxDuration, _, _ time.Duration) (*model.EmailLifecycleResult, *model.AppError) {
	s.maxDuration = maxDuration
	if s.err != nil {
		return nil, s.err
	}
	return &model.EmailLifecycleResult{Released: 1}, nil
}

// A failed cycle backs off; the cycle stops itself at half of the statement timeout.
func TestEmailLifecycleWatch(t *testing.T) {
	settings := EmailLifecycleSettings{Interval: time.Second, Batch: 10, LockTimeout: time.Second, StatementTimeout: 10 * time.Second}
	if err := settings.Validate(); err != nil {
		t.Fatal(err)
	}
	if (EmailLifecycleSettings{Interval: time.Second, LockTimeout: time.Second, StatementTimeout: time.Second, Batch: 1}).Validate() == nil {
		t.Fatal("lock timeout equal to statement timeout accepted")
	}

	st := &fakeLifecycleStore{}
	w := NewEmailLifecycleWatcher(st, settings, wlog.NewLogger(&wlog.LoggerConfiguration{}))
	if !w.Watch() || st.maxDuration != 5*time.Second {
		t.Fatalf("successful cycle failed or max duration %s", st.maxDuration)
	}

	st.err = model.NewAppError("t", model.EmailLifecycleErrorId(model.EmailDistributeLockTimeout), nil, "", 500)
	if w.Watch() || model.EmailLifecycleOutcome(st.err) != model.EmailDistributeLockTimeout {
		t.Fatal("failed cycle reported as successful or outcome lost")
	}
}
