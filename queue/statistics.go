package queue

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
)

const (
	// heavy track: refresh all stats including cc_distribute_stats
	STATISTICS_WATCHER_POLLING_INTERVAL = 1 * 1000 * 60
	// light track: refresh cc_distribute_stats_light for predictive pacing every 5 s
	STATISTICS_PACING_POLLING_INTERVAL = 1 * 1000 * 5
)

type StatisticsManager struct {
	store         store.Store
	watcher       *utils.Watcher
	pacingWatcher *utils.Watcher
	startOnce     sync.Once
	log           *wlog.Logger
}

func NewStatisticsManager(store store.Store) *StatisticsManager {
	var manager StatisticsManager
	manager.store = store
	manager.log = wlog.GlobalLogger().With(
		wlog.Namespace("context"),
		wlog.String("name", "statistics_manager"),
	)
	initPacingMetrics()
	return &manager
}

func (s *StatisticsManager) Start() {
	s.log.Debug("starting statistics service")
	s.watcher = utils.MakeWatcher("Statistics", STATISTICS_WATCHER_POLLING_INTERVAL, s.refresh)
	s.pacingWatcher = utils.MakeWatcher("PredictivePacing", STATISTICS_PACING_POLLING_INTERVAL, s.refreshPredictivePacing)
	s.startOnce.Do(func() {
		ver, err := s.store.Statistic().LibVersion()
		if err != nil {
			s.log.Error(err.Error(),
				wlog.Err(err),
			)
		}
		s.log.Debug(fmt.Sprintf("cc_sql version: %s", ver))

		go s.watcher.Start()
		go s.pacingWatcher.Start()
	})
}

func (s *StatisticsManager) Stop() {
	s.watcher.Stop()
	s.pacingWatcher.Stop()
}

func (s *StatisticsManager) refreshPredictivePacing() {
	st := time.Now()
	if err := s.store.Member().RefreshPredictivePacing(); err != nil {
		s.log.Error(err.Error(),
			wlog.Err(err),
		)
		return
	}
	s.log.Debug(fmt.Sprintf("refresh predictive pacing light stats time: %s", time.Now().Sub(st)))

	if rows, err := s.store.Member().FetchPredictivePacingStats(); err != nil {
		s.log.Error(err.Error(),
			wlog.Err(err),
		)
	} else {
		recordPacingStats(context.Background(), rows)
	}
}

func (s *StatisticsManager) refresh() {
	st := time.Now()
	var err *model.AppError
	if err = s.store.Agent().RefreshAgentPauseCauses(); err != nil {
		s.log.Error(err.Error(),
			wlog.Err(err),
		)
	}

	s.log.Debug(fmt.Sprintf("refresh pause_cause statistics time: %s", time.Now().Sub(st)))

	if err = s.store.Agent().RefreshAgentStatistics(); err != nil {
		s.log.Error(err.Error(),
			wlog.Err(err),
		)
	}

	s.log.Debug(fmt.Sprintf("refresh today statistics time: %s", time.Now().Sub(st)))

	st = time.Now()
	if err = s.store.Member().RefreshQueueStatsLast2H(); err != nil {
		s.log.Error(err.Error(),
			wlog.Err(err),
		)
	} else {
		s.log.Debug(fmt.Sprintf("refresh outbound queue statistics time: %s", time.Now().Sub(st)))
	}

	st = time.Now()
	if err = s.store.Statistic().RefreshInbound1H(); err != nil {
		s.log.Error(err.Error(),
			wlog.Err(err),
		)
	} else {
		s.log.Debug(fmt.Sprintf("refresh inbound queue statistics time: %s", time.Now().Sub(st)))
	}

	return
}
