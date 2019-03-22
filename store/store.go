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
}

type QueueStore interface {
	GetById(id int64) StoreChannel
}

type MemberStore interface {
	ReserveMembersByNode(nodeId string) StoreChannel
	UnReserveMembersByNode(nodeId, cause string) StoreChannel
	GetActiveMembersAttempt(nodeId string) StoreChannel
	AttemptOriginate(attemptId, memberId, communicationId int64) StoreChannel
	SetEndMemberAttempt(id int64, state int, hangupAt int64, result string) StoreChannel
	SetAttemptState(id int64, state int) StoreChannel
	SetBridged(id, bridgedAt int64, legAId, legBId *string) StoreChannel
	StopAttempt(attemptId int64, delta, state int, hangupAt int64, cause string) StoreChannel
}
