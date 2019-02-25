package engine

import (
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"sync"
)

var DEFAULT_WATCHER_POLLING_INTERVAL = 400

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
	mlog.Info("Starting workers")
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
