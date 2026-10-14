package rabbit

import (
	"sync/atomic"
	"testing"
	"time"

	"github.com/webitel/wlog"
)

const testBufferSize = 100

func testAMQP() *AMQP {
	return &AMQP{
		log: wlog.NewLogger(&wlog.LoggerConfiguration{}),
	}
}

func measure(fn func()) time.Duration {
	start := time.Now()
	fn()
	return time.Since(start)
}

func TestEnqueueDeliversWhileThereIsRoom(t *testing.T) {
	a := testAMQP()
	ch := make(chan int, testBufferSize)
	var stalled atomic.Bool

	took := measure(func() {
		for i := 0; i < testBufferSize; i++ {
			enqueue(a, ch, &stalled, i, "test")
		}
	})

	if took > ENQUEUE_TIMEOUT/4 {
		t.Errorf("filling the buffer took %s, it must not wait at all", took)
	}
	if len(ch) != testBufferSize {
		t.Errorf("delivered %d messages, want %d", len(ch), testBufferSize)
	}
	if stalled.Load() {
		t.Error("stream marked as stalled while it was still accepting")
	}
}

func TestEnqueueGivesUpOnAStoppedConsumer(t *testing.T) {
	a := testAMQP()
	ch := make(chan int, 1)
	var stalled atomic.Bool
	enqueue(a, ch, &stalled, 0, "test")

	took := measure(func() { enqueue(a, ch, &stalled, 1, "test") })

	if took < ENQUEUE_TIMEOUT {
		t.Errorf("gave up after %s, want at least %s", took, ENQUEUE_TIMEOUT)
	}
	if took > ENQUEUE_TIMEOUT*2 {
		t.Errorf("blocked for %s, want about %s", took, ENQUEUE_TIMEOUT)
	}
	if !stalled.Load() {
		t.Error("stream not marked as stalled after the wait expired")
	}
}

// This is the property the whole service leans on: enqueue runs on the single goroutine
// that reads AMQP deliveries, so once a stream is known to be stalled it must be skipped
// outright. Paying the wait per message would stop every other stream too.
func TestEnqueueWaitsOnlyOncePerStall(t *testing.T) {
	a := testAMQP()
	ch := make(chan int, 1)
	var stalled atomic.Bool
	enqueue(a, ch, &stalled, 0, "test")
	enqueue(a, ch, &stalled, 1, "test") // pays the wait, marks the stream stalled

	took := measure(func() {
		for i := 0; i < 1000; i++ {
			enqueue(a, ch, &stalled, i, "test")
		}
	})

	if took > ENQUEUE_TIMEOUT/4 {
		t.Errorf("1000 further messages took %s, they must be dropped immediately", took)
	}
}

func TestEnqueueRecoversWhenTheConsumerResumes(t *testing.T) {
	a := testAMQP()
	ch := make(chan int, 1)
	var stalled atomic.Bool
	enqueue(a, ch, &stalled, 0, "test")
	enqueue(a, ch, &stalled, 1, "test")

	if !stalled.Load() {
		t.Fatal("stream not marked as stalled, the rest of the test is meaningless")
	}

	<-ch // the consumer starts reading again

	enqueue(a, ch, &stalled, 2, "test")

	if stalled.Load() {
		t.Error("stream still marked as stalled after a successful delivery")
	}
	if len(ch) != 1 {
		t.Errorf("buffer holds %d messages, want 1 - the message was dropped instead of delivered", len(ch))
	}
}

func TestEnqueueReachesASlowConsumer(t *testing.T) {
	a := testAMQP()
	ch := make(chan int, 1)
	var stalled atomic.Bool
	enqueue(a, ch, &stalled, 0, "test")

	go func() {
		time.Sleep(ENQUEUE_TIMEOUT / 8)
		<-ch
	}()

	enqueue(a, ch, &stalled, 1, "test")

	if stalled.Load() {
		t.Error("stream marked as stalled although the consumer caught up in time")
	}
	if len(ch) != 1 {
		t.Errorf("buffer holds %d messages, want 1 - the message was dropped instead of delivered", len(ch))
	}
}

// One stalled stream must not hold up the others. A chat consumer that stopped reading
// is what took call events down with it on 2026-09-28.
func TestEnqueueStallIsPerStream(t *testing.T) {
	a := testAMQP()
	chats := make(chan int, 1)
	calls := make(chan int, testBufferSize)
	var chatStalled, callStalled atomic.Bool

	enqueue(a, chats, &chatStalled, 0, "chat")
	enqueue(a, chats, &chatStalled, 1, "chat") // chat stream stalls here

	took := measure(func() {
		for i := 0; i < testBufferSize; i++ {
			enqueue(a, calls, &callStalled, i, "call")
		}
	})

	if took > ENQUEUE_TIMEOUT/4 {
		t.Errorf("call stream took %s while the chat stream was stalled", took)
	}
	if callStalled.Load() {
		t.Error("call stream marked as stalled because the chat stream was")
	}
	if len(calls) != testBufferSize {
		t.Errorf("delivered %d call messages, want %d", len(calls), testBufferSize)
	}
}
