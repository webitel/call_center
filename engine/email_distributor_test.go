package engine

import (
	"testing"
	"time"

	"github.com/webitel/call_center/model"
)

func TestSummarizeEmailCycle(t *testing.T) {
	q := func(id int32) *int32 { return &id }
	c := SummarizeEmailCycle([]*model.EmailDistributeResult{
		{Result: model.EmailDistributeAssigned, QueueId: q(1)},
		{Result: model.EmailDistributeAssigned, QueueId: q(1)},
		{Result: model.EmailDistributeNoAgent, QueueId: q(1)},
		{Result: model.EmailDistributeCalendarClosed, QueueId: q(2)},
		{Result: model.EmailDistributeNoSkills, QueueId: q(3)},
		{Result: model.EmailDistributeCalendarInvalid, QueueId: q(4)},
	})
	if c.Busy || c.Assigned != 2 || c.NoAgentQueues != 1 || c.ClosedQueues != 1 ||
		len(c.NoSkillsQueues) != 1 || c.NoSkillsQueues[0] != 3 || len(c.InvalidCalendar) != 1 || c.InvalidCalendar[0] != 4 {
		t.Fatalf("unexpected summary %+v", c)
	}

	if !SummarizeEmailCycle([]*model.EmailDistributeResult{{Result: model.EmailDistributeBusy}}).Busy {
		t.Fatal("busy lock is not reported")
	}
	if !SummarizeEmailCycle([]*model.EmailDistributeResult{{Result: model.EmailDistributeTimeLimit, QueueId: q(1)}}).TimeLimited {
		t.Fatal("time limit is not reported")
	}
}

func TestEmailDistributorWarnsOncePerPeriod(t *testing.T) {
	d := &EmailDistributor{warned: make(map[string]time.Time)}
	now := time.Now()
	if !d.shouldWarn("no_skills:3", now) || d.shouldWarn("no_skills:3", now.Add(time.Minute)) {
		t.Fatal("repeated warning within the period")
	}
	if !d.shouldWarn("no_skills:4", now) || !d.shouldWarn("no_skills:3", now.Add(emailWarnEvery)) {
		t.Fatal("warning suppressed for another queue or after the period")
	}
}

func TestEmailDistributorSettingsValidate(t *testing.T) {
	ok := EmailDistributorSettings{Interval: time.Second, QueueBatch: 1, LockTimeout: time.Second, StatementTimeout: 10 * time.Second}
	if err := ok.Validate(); err != nil {
		t.Fatal(err)
	}
	bad := ok
	bad.QueueBatch = 0
	if bad.Validate() == nil {
		t.Fatal("zero queue batch accepted")
	}
}
