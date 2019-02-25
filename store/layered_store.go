package store

import (
	"context"
)

type LayeredStoreDatabaseLayer interface {
	LayeredStoreSupplier
	Store
}

type LayeredStore struct {
	TmpContext     context.Context
	DatabaseLayer  LayeredStoreDatabaseLayer
	LayerChainHead LayeredStoreSupplier
}

func NewLayeredStore(db LayeredStoreDatabaseLayer) Store {
	store := &LayeredStore{
		TmpContext:    context.TODO(),
		DatabaseLayer: db,
	}

	return store
}

type QueryFunction func(LayeredStoreSupplier) *LayeredStoreSupplierResult

func (s *LayeredStore) RunQuery(queryFunction QueryFunction) StoreChannel {
	storeChannel := make(StoreChannel)

	go func() {
		result := queryFunction(s.LayerChainHead)
		storeChannel <- result.StoreResult
	}()

	return storeChannel
}

func (s *LayeredStore) Session() SessionStore {
	return s.DatabaseLayer.Session()
}
func (s *LayeredStore) Queue() QueueStore {
	return s.DatabaseLayer.Queue()
}

func (s *LayeredStore) Calendar() CalendarStore {
	return s.DatabaseLayer.Calendar()
}

func (s *LayeredStore) Member() MemberStore {
	return s.DatabaseLayer.Member()
}
