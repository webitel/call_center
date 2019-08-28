package call_manager

import (
	"fmt"
	"github.com/webitel/call_center/cluster"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"sync"
)

const (
	MAX_CALL_CACHE         = 10000
	MAX_CALL_EXPIRE_CACHE  = 60 * 60 * 24 //day
	MAX_INBOUND_CALL_QUEUE = 1000

	WATCHER_INTERVAL = 1000 * 5 // 30s
)

type CallManager interface {
	Start()
	Stop()
	ActiveCalls() int
	NewCall(callRequest *model.CallRequest) Call
	GetCall(id string) (Call, bool)
	InboundCall() <-chan Call
}

type CallManagerImpl struct {
	nodeId string

	pool        *callConnectionsPool
	mq          mq.MQ
	calls       utils.ObjectCache
	stop        chan struct{}
	stopped     chan struct{}
	inboundCall chan Call
	watcher     *utils.Watcher
	startOnce   sync.Once
}

func NewCallManager(nodeId string, cluster cluster.ServiceDiscovery, mq mq.MQ) CallManager {
	return &CallManagerImpl{
		nodeId:      nodeId,
		pool:        newCallConnectionsPool(cluster),
		mq:          mq,
		stop:        make(chan struct{}),
		stopped:     make(chan struct{}),
		inboundCall: make(chan Call, MAX_INBOUND_CALL_QUEUE),
		calls:       utils.NewLruWithParams(MAX_CALL_CACHE, "CallManager", MAX_CALL_EXPIRE_CACHE, ""),
	}
}

func (cm *CallManagerImpl) Start() {
	wlog.Debug("callManager started")

	cm.startOnce.Do(func() {
		cm.watcher = utils.MakeWatcher("CallManager", WATCHER_INTERVAL, cm.pool.checkConnection)
		go cm.watcher.Start()
		go func() {
			defer func() {
				wlog.Debug("stopped CallManager")
				close(cm.stopped)
			}()

			for {
				select {
				case <-cm.stop:
					wlog.Debug("callManager received stop signal")
					return
				case e, ok := <-cm.mq.ConsumeCallEvent():
					if !ok {
						return
					}

					cm.handleCallEvent(e)
				}
			}
		}()
	})
}

func (cm *CallManagerImpl) Stop() {
	wlog.Debug("callManager Stopping")

	if cm.watcher != nil {
		cm.watcher.Stop()
	}
	cm.pool.closeAllConnections()
	close(cm.stop)
	<-cm.stopped
}

func (cm *CallManagerImpl) NewCall(callRequest *model.CallRequest) Call {
	api, _ := cm.pool.getByRoundRobin() //TODO check error
	return NewCall(CALL_DIRECTION_OUTBOUND, callRequest, cm, api)
}

func (cm *CallManagerImpl) ActiveCalls() int {
	return cm.calls.Len()
}

func (cm *CallManagerImpl) GetCall(id string) (Call, bool) {
	if call, ok := cm.calls.Get(id); ok {
		return call.(Call), true
	}
	return nil, false
}

func (cm *CallManagerImpl) saveToCacheCall(call Call) {
	wlog.Debug(fmt.Sprintf("[%s] call %s save to store", call.NodeName(), call.Id()))
	cm.calls.AddWithDefaultExpires(call.Id(), call)
}

func (cm *CallManagerImpl) removeFromCacheCall(call Call) {
	wlog.Debug(fmt.Sprintf("[%s] call %s remove from store", call.NodeName(), call.Id()))
	cm.calls.Remove(call.Id())
}

func (cm *CallManagerImpl) InboundCall() <-chan Call {
	return cm.inboundCall
}
