package queue

import (
	"sync"

	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
)

const (
	waitingListPollingInterval = 1000
)

var (
	startOnceWaitingList sync.Once
	waitingListWatcher   *utils.Watcher
)

func (qm *Manager) listenWaitingList() {
	startOnceWaitingList.Do(func() {
		waitingListWatcher = utils.MakeWatcher("WaitingList", waitingListPollingInterval, qm.listWaiting)
		go waitingListWatcher.Start()
	})
}

func (qm *Manager) stopWaitingList() {
	if waitingListWatcher != nil {
		waitingListWatcher.Stop()
	}
}

func (qm *Manager) listWaiting() {
	list, err := qm.store.Member().WaitingList(qm.app.Context())
	if err != nil {
		qm.log.Error("getting waiting list", wlog.Err(err))

		return
	}

	for _, v := range list {
		if err = qm.app.NotificationWaitingList(v); err != nil {
			qm.log.Error("notifying waiting list", wlog.Err(err))
		}
	}
}
