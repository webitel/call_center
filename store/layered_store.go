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

func (s *LayeredStore) Cluster() ClusterStore {
	return s.DatabaseLayer.Cluster()
}

func (s *LayeredStore) OutboundResource() OutboundResourceStore {
	return s.DatabaseLayer.OutboundResource()
}

func (s *LayeredStore) Queue() QueueStore {
	return s.DatabaseLayer.Queue()
}

func (s *LayeredStore) Member() MemberStore {
	return s.DatabaseLayer.Member()
}

func (s *LayeredStore) Agent() AgentStore {
	return s.DatabaseLayer.Agent()
}

func (s *LayeredStore) Team() TeamStore {
	return s.DatabaseLayer.Team()
}

func (s *LayeredStore) Gateway() GatewayStore {
	return s.DatabaseLayer.Gateway()
}

func (s *LayeredStore) Call() CallStore {
	return s.DatabaseLayer.Call()
}
