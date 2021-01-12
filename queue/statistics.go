package queue

import (
	"fmt"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"sync"
)

const (
	STATISTICS_WATCHER_POLLING_INTERVAL = 5 * 1000 * 60
)

type StatisticsManager struct {
	store     store.Store
	watcher   *utils.Watcher
	startOnce sync.Once
}

func NewStatisticsManager(store store.Store) *StatisticsManager {
	var manager StatisticsManager
	manager.store = store
	return &manager
}

func (s *StatisticsManager) Start() {
	wlog.Debug("starting statistics service")
	s.watcher = utils.MakeWatcher("Statistics", STATISTICS_WATCHER_POLLING_INTERVAL, s.refresh)
	s.startOnce.Do(func() {
		go s.watcher.Start()
	})
}

func (s *StatisticsManager) Stop() {
	s.watcher.Stop()
}

func (s *StatisticsManager) refresh() {
	wlog.Debug("refresh statistics start")
	return
	if err := s.store.Queue().RefreshStatisticsDay5Min(); err != nil {
		wlog.Error(fmt.Sprintf("refresh member statistics error: %s", err.Error()))
	} else {
		wlog.Debug("refresh member statistics ")
	}

	if err := s.store.Agent().RefreshEndStateDay5Min(); err != nil {
		wlog.Error(fmt.Sprintf("refresh agent statistics error: %s", err.Error()))
	} else {
		wlog.Debug("refresh agent statistics ")
	}
}
