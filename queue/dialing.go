package queue

import (
	"context"
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/mq"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"sync"
	"time"
)

var DEFAULT_WATCHER_POLLING_INTERVAL = 400

type DialingImpl struct {
	app               App
	store             store.Store
	watcher           *utils.Watcher
	queueManager      *Manager
	resourceManager   *ResourceManager
	statisticsManager *StatisticsManager
	expiredManager    *ExpiredManager
	agentManager      agent_manager.AgentManager
	callManager       call_manager.CallManager
	startOnce         sync.Once
	log               *wlog.Logger
}

func NewDialing(app App, m mq.MQ, callManager call_manager.CallManager, agentManager agent_manager.AgentManager, s store.Store, bridgeSleep time.Duration) Dialing {
	var dialing DialingImpl
	dialing.app = app
	dialing.store = s
	dialing.agentManager = agentManager
	dialing.resourceManager = NewResourceManager(app)
	dialing.statisticsManager = NewStatisticsManager(s)
	dialing.expiredManager = NewExpiredManager(app, s)
	dialing.queueManager = NewQueueManager(app, s, m, callManager, dialing.resourceManager, agentManager, bridgeSleep)
	dialing.log = dialing.queueManager.log.With(
		wlog.Namespace("context"),
		wlog.String("name", "dialing_manager"),
	)
	return &dialing
}

func (d *DialingImpl) Manager() *Manager {
	return d.queueManager
}

func (d *DialingImpl) Start() {
	d.log.Debug("starting dialing service")
	d.watcher = utils.MakeWatcher("Dialing", DEFAULT_WATCHER_POLLING_INTERVAL, d.routeData)

	d.startOnce.Do(func() {
		go d.watcher.Start()
		go d.queueManager.Start()
		go d.statisticsManager.Start()
		go d.expiredManager.Start()
	})
}

func (d *DialingImpl) Stop() {
	d.queueManager.Stop()
	d.watcher.Stop()
	d.statisticsManager.Stop()
	d.expiredManager.Stop()
}

func (d *DialingImpl) routeData() {
	d.routeIdleAttempts()
	d.routeIdleAgents()
}

func (d *DialingImpl) routeIdleAttempts() {
	if !d.app.IsReady() {
		return
	}

	if channels, err := d.store.Agent().GetChannelTimeout(); err == nil {
		for _, v := range channels {
			//todo
			waiting := NewWaitingChannelEvent(v.Channel, v.UserId, nil, v.Timestamp)
			//FIXME QueueId ?
			err = d.queueManager.mq.AgentChannelEvent(v.Channel, v.DomainId, 0, v.UserId, waiting)
		}
	} else {
		d.log.Error(err.Error(),
			wlog.Err(err),
		) ///TODO return ?
	}

	members, err := d.store.Member().GetActiveMembersAttempt(d.app.GetInstanceId())
	if err != nil {
		d.log.Error(err.Error(),
			wlog.Err(err),
		)
		time.Sleep(time.Second)
		return
	}

	for _, v := range members {
		if v.MemberId == nil {
			d.log.Warn(fmt.Sprintf("Attempt=%d is canceled", v.Id),
				wlog.Int64("attempt_id", v.Id),
			)
			continue
		}
		v.CreatedAt = time.Now()
		att, _ := d.queueManager.CreateAttemptIfNotExists(context.Background(), v) //todo check err
		att.Log("state: " + att.state)
		d.queueManager.input <- att
	}
}

func (d *DialingImpl) routeIdleAgents() {
	if !d.app.IsReady() {
		return
	}

	//// FIXME engine
	if attempts, err := d.store.Member().GetTimeouts(d.app.GetInstanceId()); err == nil {
		for _, v := range attempts {
			waiting := NewWaitingChannelEvent(v.Channel, v.UserId, &v.AttemptId, v.Timestamp)
			err = d.queueManager.mq.AgentChannelEvent(v.Channel, v.DomainId, 0, v.UserId, waiting)

			if a, ok := d.queueManager.GetAttempt(v.AttemptId); ok {
				a.SetResult(AttemptResultTimeout)

				if v.AfterSchemaId == nil {
					d.queueManager.LeavingMember(a)
				} else {
					d.queueManager.TimeoutLeavingMember(a)
				}
			} else {
				// TODO
				d.queueManager.store.Member().SetTimeoutError(v.AttemptId)
				d.log.Error("attempt[%d] error: not found in cache, set timeout error")
			}
		}
	} else {
		d.log.Error(err.Error(),
			wlog.Err(err),
		) ///TODO return ?
	}
	// FIXME engine
	if hists, err := d.store.Member().SaveToHistory(); err == nil {
		for _, h := range hists {
			d.log.Debug(fmt.Sprintf("Attempt=%d result %s", h.Id, h.Result),
				wlog.Int64("attempt_id", h.Id),
				wlog.String("result", h.Result),
			)
		}
	} else {
		d.log.Error(err.Error(),
			wlog.Err(err),
		)
		time.Sleep(time.Second)
	}

	result, err := d.store.Agent().ReservedForAttemptByNode(d.app.GetInstanceId())
	if err != nil {
		d.log.Error(err.Error(),
			wlog.Err(err),
		)
		time.Sleep(time.Second)
		return
	}

	for _, v := range result {
		agent, err := d.agentManager.GetAgent(v.AgentId, v.AgentUpdatedAt)
		if err != nil {
			d.log.Error(err.Error(),
				wlog.Err(err),
			)
			continue
		}
		agent.SetTeamUpdatedAt(v.TeamUpdatedAt)
		d.routeAgentToAttempt(v.AttemptId, agent)
	}
}

func (d *DialingImpl) routeAgentToAttempt(attemptId int64, agent agent_manager.AgentObject) {
	if attempt, ok := d.queueManager.membersCache.Get(attemptId); ok {
		att := attempt.(*Attempt)
		if _, err := d.queueManager.GetQueue(att.QueueId(), att.QueueUpdatedAt()); err == nil {
			att.DistributeAgent(agent)
		} else {
			att.log.Error(fmt.Sprintf("Not found queue AttemptId=%d for agent %s", attemptId, agent.Name()),
				wlog.Err(err),
			)
		}
	} else {
		d.log.Error(fmt.Sprintf("Not found active attempt Id=%d for agent %s", attemptId, agent.Name()),
			wlog.Int64("attempt_id", attemptId),
		)
	}
}
