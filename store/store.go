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
	Member() MemberStore
	OutboundResource() OutboundResourceStore
}

type SessionStore interface {
	Get(sessionIdOrToken string) StoreChannel
}

type CalendarStore interface {
	Create(calendar *model.Calendar) StoreChannel
	GetAllPage(filter string, offset, limit int, sortField string, desc bool) StoreChannel
	Get(id int) StoreChannel
	Delete(id int) StoreChannel
}

type OutboundResourceStore interface {
	GetById(id int64) StoreChannel
	GetAllPage(filter string, offset, limit int, sortField string, desc bool) StoreChannel
	Create(resource *model.OutboundResource) StoreChannel
	Delete(id int64) StoreChannel
	SetError(id int64, routingId int64, errorId string, strategy model.OutboundResourceUnReserveStrategy) StoreChannel
	SetSuccessivelyErrorsById(id int64, successivelyErrors uint16) StoreChannel
}

type QueueStore interface {
	GetById(id int64) StoreChannel
}

type MemberStore interface {
	ReserveMembersByNode(nodeId string) StoreChannel
	UnReserveMembersByNode(nodeId, cause string) StoreChannel
	GetActiveMembersAttempt(nodeId string) StoreChannel

	SetAttemptState(id int64, state int) StoreChannel
	SetBridged(id, bridgedAt int64, legAId, legBId *string) StoreChannel
	ActiveCount(queue_id int64) StoreChannel

	SetAttemptSuccess(attemptId, hangupAt int64, cause string, data []byte) StoreChannel
	SetAttemptStop(attemptId, hangupAt int64, delta int, isErr bool, cause string, data []byte) StoreChannel
}
