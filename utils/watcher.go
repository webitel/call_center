package utils

import (
	"fmt"
	"github.com/webitel/wlog"
	"time"
)

type WatcherNotify func()

type Watcher struct {
	name            string
	stop            chan struct{}
	stopped         chan struct{}
	pollingInterval int
	PollAndNotify   WatcherNotify
	log             *wlog.Logger
}

func MakeWatcher(name string, pollingInterval int, pollAndNotify WatcherNotify) *Watcher {
	return &Watcher{
		name:            name,
		stop:            make(chan struct{}),
		stopped:         make(chan struct{}),
		pollingInterval: pollingInterval,
		PollAndNotify:   pollAndNotify,
		log: wlog.GlobalLogger().With(
			wlog.Namespace("context"),
			wlog.String("name", "watcher"),
			wlog.String("watcher", name),
		),
	}
}

func (watcher *Watcher) Start() {
	watcher.log.Debug(fmt.Sprintf("watcher [%s] started", watcher.name))
	//<-time.After(time.Duration(rand.Intn(watcher.pollingInterval)) * time.Millisecond)

	defer func() {
		watcher.log.Debug(fmt.Sprintf("watcher [%s] finished", watcher.name))
		close(watcher.stopped)
	}()

	for {
		select {
		case <-watcher.stop:
			watcher.log.Debug(fmt.Sprintf("watcher [%s] received stop signal", watcher.name))
			return
		case <-time.After(time.Duration(watcher.pollingInterval) * time.Millisecond):
			watcher.PollAndNotify()
		}
	}
}

func (watcher *Watcher) Stop() {
	watcher.log.Debug(fmt.Sprintf("watcher [%s] stopping", watcher.name))
	close(watcher.stop)
	<-watcher.stopped
}
