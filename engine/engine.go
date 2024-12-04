package engine

import (
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"sync"
	"time"
)

type App interface {
	IsReady() bool
}

type EngineImp struct {
	app               App
	nodeId            string
	store             store.Store
	startOnce         sync.Once
	pollingInterval   time.Duration
	watcher           *utils.Watcher
	enableOmnichannel bool
	log               *wlog.Logger
}

func NewEngine(app App, id string, s store.Store, enableOmnichannel bool, pollingInterval time.Duration, log *wlog.Logger) Engine {
	return &EngineImp{
		app:               app,
		nodeId:            id,
		store:             s,
		pollingInterval:   pollingInterval,
		enableOmnichannel: enableOmnichannel,
		log: log.With(
			wlog.Namespace("context"),
			wlog.String("name", "engine"),
		),
	}
}

func (e *EngineImp) Start() {
	e.log.Info("starting engine service")
	e.watcher = utils.MakeWatcher("Engine", int(e.pollingInterval.Milliseconds()), e.ReserveMembers)
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
