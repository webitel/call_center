package queue

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"sync"
	"time"
)

const (
	STATISTICS_WATCHER_POLLING_INTERVAL = 1 * 1000 * 60
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
	st := time.Now()
	var err *model.AppError
	if err = s.store.Agent().RefreshAgentPauseCauses(); err != nil {
		wlog.Error(err.Error())
	}

	wlog.Debug(fmt.Sprintf("refresh pause_cause statistics time: %s", time.Now().Sub(st)))

	if err = s.store.Agent().RefreshAgentStatistics(); err != nil {
		wlog.Error(err.Error())
	}

	wlog.Debug(fmt.Sprintf("refresh today statistics time: %s", time.Now().Sub(st)))

	st = time.Now()
	if err = s.store.Member().RefreshQueueStatsLast2H(); err != nil {
		wlog.Error(err.Error())
	} else {
		wlog.Debug(fmt.Sprintf("refresh outbound queue statistics time: %s", time.Now().Sub(st)))
	}

	st = time.Now()
	if err = s.store.Statistic().RefreshInbound1H(); err != nil {
		wlog.Error(err.Error())
	} else {
		wlog.Debug(fmt.Sprintf("refresh inbound queue statistics time: %s", time.Now().Sub(st)))
	}

	st = time.Now()
	if _, err = s.store.Member().SetExpired(); err != nil {
		wlog.Error(err.Error())
	} else {
		wlog.Debug(fmt.Sprintf("set expired members time: %s", time.Now().Sub(st)))
	}

	return
}
