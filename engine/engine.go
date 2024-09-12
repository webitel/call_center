package engine

import (
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"sync"
)

var DEFAULT_WATCHER_POLLING_INTERVAL = 500

type App interface {
	IsReady() bool
}

type EngineImp struct {
	app               App
	nodeId            string
	store             store.Store
	startOnce         sync.Once
	pollingInterval   int
	watcher           *utils.Watcher
	enableOmnichannel bool
}

func NewEngine(app App, id string, s store.Store, enableOmnichannel bool) Engine {
	return &EngineImp{
		app:               app,
		nodeId:            id,
		store:             s,
		pollingInterval:   DEFAULT_WATCHER_POLLING_INTERVAL,
		enableOmnichannel: enableOmnichannel,
	}
}

func (e *EngineImp) Start() {
	wlog.Info("starting engine service")
	e.watcher = utils.MakeWatcher("Engine", e.pollingInterval, e.ReserveMembers)
	e.UnReserveMembers()
	//e.CleanAllAttempts()
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
