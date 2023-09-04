package queue

import (
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"sync"
)

const (
	waitingListPollingInterval = 1000
)

var (
	startOnceWaitingList sync.Once
	waitingListWatcher   *utils.Watcher
)

func (qm *QueueManager) listenWaitingList() {
	startOnceWaitingList.Do(func() {
		waitingListWatcher = utils.MakeWatcher("WaitingList", waitingListPollingInterval, qm.listWaiting)
		waitingListWatcher.Start()
	})
}

func (qm *QueueManager) stopWaitingList() {
	if waitingListWatcher != nil {
		waitingListWatcher.Stop()
	}
}

func (qm *QueueManager) listWaiting() {
	list, err := qm.store.Member().WaitingList()
	if err != nil {
		wlog.Error(err.Error())
		return
	}

	for _, v := range list {
		err = qm.app.NotificationWaitingList(v.DomainId, v.Users, v.Members)
		if err != nil {
			wlog.Error(err.Error())
		}
	}
}
