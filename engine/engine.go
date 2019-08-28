package engine

import (
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"sync"
)

var DEFAULT_WATCHER_POLLING_INTERVAL = 600

type EngineImp struct {
	nodeId          string
	store           store.Store
	startOnce       sync.Once
	pollingInterval int
	watcher         *utils.Watcher
}

func NewEngine(id string, s store.Store) Engine {
	return &EngineImp{
		nodeId:          id,
		store:           s,
		pollingInterval: DEFAULT_WATCHER_POLLING_INTERVAL,
	}
}

func (e *EngineImp) Start() {
	wlog.Info("starting engine service")
	e.watcher = utils.MakeWatcher("Engine", e.pollingInterval, e.ReserveMembers)
	e.UnReserveMembers()
	e.startOnce.Do(func() {
		go e.watcher.Start()
	})
}

func (e *EngineImp) Stop() {
	if e.watcher != nil {
		e.watcher.Stop()
	}
	e.UnReserveMembers()
}
