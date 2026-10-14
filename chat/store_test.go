package chat_test

import (
	"sync"
	"testing"

	"github.com/pborman/uuid"
	"github.com/webitel/call_center/chat"
	"github.com/webitel/wlog"
)

const mockConsulAddr = "127.0.0.1:8500"

func newDummyLogger() *wlog.Logger { return wlog.NewLogger(&wlog.LoggerConfiguration{}) }

func Test_Create_Delete_Conversation_Race(t *testing.T) {
	manager := chat.NewChatManager(mockConsulAddr, nil, newDummyLogger())

	const iterations = 10_000
	lost := 0

	for range iterations {
		id := uuid.New()
		oldConv, err := manager.NewConversation(1, id, "10", "11", map[string]string{})
		if err != nil {
			t.Fatalf("creating first conversation object: %+v", err)
		}

		newConv, err := manager.NewConversation(1, id, "10", "11", map[string]string{})
		if err != nil {
			t.Fatalf("creating second conversation object: %+v", err)
		}

		manager.StoreConversation(oldConv)

		start := make(chan struct{})
		var wg sync.WaitGroup
		wg.Add(2)

		go func() {
			defer wg.Done()
			<-start
			manager.RemoveConversation(oldConv)
		}()
		go func() {
			defer wg.Done()
			<-start
			manager.StoreConversation(newConv)
		}()

		close(start)
		wg.Wait()

		if _, err := manager.GetConversation(id); err != nil {
			lost++
		}
	}

	if lost > 0 {
		t.Fatalf("new chat was deleted by stale Remove: %d/%d iterations", lost, iterations)
	}
}
