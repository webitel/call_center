package utils

import (
	"fmt"
	"github.com/webitel/call_center/mlog"
	"math/rand"
	"time"
)

type WatcherNotify func()

type Watcher struct {
	name            string
	stop            chan struct{}
	stopped         chan struct{}
	pollingInterval int
	PollAndNotify   WatcherNotify
}

func MakeWatcher(name string, pollingInterval int, pollAndNotify WatcherNotify) *Watcher {
	return &Watcher{
		name:            name,
		stop:            make(chan struct{}),
		stopped:         make(chan struct{}),
		pollingInterval: pollingInterval,
		PollAndNotify:   pollAndNotify,
	}
}

func (watcher *Watcher) Start() {
	mlog.Debug(fmt.Sprintf("Watcher [%s] started", watcher.name))

	rand.Seed(time.Now().UTC().UnixNano())
	//<-time.After(time.Duration(rand.Intn(watcher.pollingInterval)) * time.Millisecond)

	defer func() {
		mlog.Debug(fmt.Sprintf("Watcher [%s] finished", watcher.name))
		close(watcher.stopped)
	}()

	for {
		select {
		case <-watcher.stop:
			mlog.Debug(fmt.Sprintf("Watcher [%s] Received stop signal", watcher.name))
			return
		case <-time.After(time.Duration(watcher.pollingInterval) * time.Millisecond):
			watcher.PollAndNotify()
		}
	}
}

func (watcher *Watcher) Stop() {
	mlog.Debug(fmt.Sprintf("Watcher [%s] Stopping", watcher.name))
	close(watcher.stop)
	<-watcher.stopped
}
