package chat

import (
	"testing"
	"time"

	"github.com/webitel/wlog"
)

func testConversation() *Conversation {
	return &Conversation{
		id: "test-conversation",
		// setClose reaches for the member session, a conversation always has one
		sessions: []*ChatSession{{ConversationId: "test-conversation"}},
		state:    make(chan ChatState, STATE_BUFFER_SIZE),
		log:      wlog.NewLogger(&wlog.LoggerConfiguration{}),
	}
}

// measure returns how long fn took, so the tests can assert on "immediately" and
// "waited once" instead of on log output.
func measure(fn func()) time.Duration {
	start := time.Now()
	fn()
	return time.Since(start)
}

func TestPushStateFillsBufferWithoutWaiting(t *testing.T) {
	c := testConversation()

	took := measure(func() {
		for i := 0; i < STATE_BUFFER_SIZE; i++ {
			c.pushState(ChatStateClose)
		}
	})

	if took > STATE_SEND_TIMEOUT/2 {
		t.Errorf("filling the buffer took %s, it must not wait at all", took)
	}
	if len(c.state) != STATE_BUFFER_SIZE {
		t.Errorf("buffered %d states, want %d", len(c.state), STATE_BUFFER_SIZE)
	}
	if c.stateStalled.Load() {
		t.Error("conversation marked as stalled while the buffer was still accepting")
	}
}

func TestPushStateGivesUpWhenNobodyReads(t *testing.T) {
	c := testConversation()
	for i := 0; i < STATE_BUFFER_SIZE; i++ {
		c.pushState(ChatStateClose)
	}

	took := measure(func() { c.pushState(ChatStateClose) })

	if took < STATE_SEND_TIMEOUT {
		t.Errorf("gave up after %s, want at least %s - a merely slow reader deserves the wait", took, STATE_SEND_TIMEOUT)
	}
	if took > STATE_SEND_TIMEOUT*2 {
		t.Errorf("blocked for %s, want about %s", took, STATE_SEND_TIMEOUT)
	}
	if !c.stateStalled.Load() {
		t.Error("conversation not marked as stalled after the wait expired")
	}
}

// The wait must be paid once per conversation. pushState runs on the goroutine that
// drains every chat event, which is what keeps the AMQP reader moving, so a wait
// repeated per event would stall call processing as well.
func TestPushStateWaitsOnlyOnce(t *testing.T) {
	c := testConversation()
	for i := 0; i < STATE_BUFFER_SIZE; i++ {
		c.pushState(ChatStateClose)
	}
	c.pushState(ChatStateClose) // pays the wait, marks the conversation stalled

	took := measure(func() {
		for i := 0; i < 20; i++ {
			c.pushState(ChatStateClose)
		}
	})

	if took > STATE_SEND_TIMEOUT/2 {
		t.Errorf("20 further states took %s, they must be dropped immediately", took)
	}
}

func TestPushStateReachesASlowReader(t *testing.T) {
	c := testConversation()
	for i := 0; i < STATE_BUFFER_SIZE; i++ {
		c.pushState(ChatStateClose)
	}

	go func() {
		time.Sleep(STATE_SEND_TIMEOUT / 4)
		<-c.state
	}()

	c.pushState(ChatStateBridge)

	if c.stateStalled.Load() {
		t.Error("conversation marked as stalled although the reader caught up in time")
	}
	if len(c.state) != STATE_BUFFER_SIZE {
		t.Errorf("buffer holds %d states, want %d - the state was dropped instead of delivered", len(c.state), STATE_BUFFER_SIZE)
	}
}

// Regression for the 2026-09-28 outage: one blind transfer produced seven
// leave_conversation events for a conversation whose queue goroutine had already
// exited. With a five slot buffer and a plain channel send the seventh blocked
// forever, which stopped chat processing and then all AMQP consumption.
func TestPushStateSurvivesTransferBurstWithoutReader(t *testing.T) {
	c := testConversation()

	done := make(chan struct{})
	go func() {
		defer close(done)
		for i := 0; i < 7; i++ {
			c.setClose(time.Now().Unix(), "TRANSFER")
		}
	}()

	select {
	case <-done:
	case <-time.After(STATE_SEND_TIMEOUT * 3):
		t.Fatal("a burst of seven leave events blocked the caller - this is the outage")
	}
}
