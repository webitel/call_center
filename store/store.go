package store

import (
	"time"

	"github.com/webitel/call_center/model"
)

type StoreResult struct {
	Data interface{}
	Err  *model.AppError
}

type StoreChannel chan StoreResult

func Do(f func(result *StoreResult)) StoreChannel {
	storeChannel := make(StoreChannel, 1)
	go func() {
		result := StoreResult{}
		f(&result)
		storeChannel <- result
		close(storeChannel)
	}()
	return storeChannel
}

func Must(sc StoreChannel) interface{} {
	r := <-sc
	if r.Err != nil {

		time.Sleep(time.Second)
		panic(r.Err)
	}

	return r.Data
}

type Store interface {
	Session() SessionStore
	Queue() QueueStore
	Calendar() CalendarStore
}

type SessionStore interface {
	Get(sessionIdOrToken string) StoreChannel
}

type CalendarStore interface {
	GetAllPage(filter string, offset, limit int, sortField string, desc bool) StoreChannel
}

type QueueStore interface {
}
