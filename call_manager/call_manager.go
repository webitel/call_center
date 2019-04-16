package call_manager

import (
	"fmt"
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
	"github.com/webitel/storage/utils"
	"sync"
)

const (
	MAX_CALL_CACHE        = 10000
	MAX_CALL_EXPIRE_CACHE = 60 * 60 * 24 //day
)

type CallManager interface {
	Start()
	Stop()
	NewCall(callRequest *model.CallRequest) Call
}

type Call interface {
	Id() string
	HangupCause() string
	Err() *model.AppError
	SetHangupCall(event mq.Event)

	WaitHangup()

	Hangup(cause string) *model.AppError
}

type CallManagerImpl struct {
	nodeId       string
	callCommands model.CallCommands
	mq           mq.MQ
	calls        utils.ObjectCache
	stop         chan struct{}
	stopped      chan struct{}
	startOnce    sync.Once
}

func NewCallManager(nodeId string, cc model.CallCommands, mq mq.MQ) CallManager {
	return &CallManagerImpl{
		nodeId:       nodeId,
		callCommands: cc,
		mq:           mq,
		stop:         make(chan struct{}),
		stopped:      make(chan struct{}),
		calls:        utils.NewLruWithParams(MAX_CALL_CACHE, "CallManager", MAX_CALL_EXPIRE_CACHE, ""),
	}
}

func (cm *CallManagerImpl) Start() {
	mlog.Debug("CallManager started")

	defer func() {
		mlog.Debug("Stopped CallManager")
		close(cm.stopped)
	}()

	cm.startOnce.Do(func() {
		go func() {
			for {
				select {
				case <-cm.stop:
					mlog.Debug("CallManager received stop signal")
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
	mlog.Debug("CallManager Stopping")
	close(cm.stop)
	<-cm.stopped
}

func (cm *CallManagerImpl) NewCall(callRequest *model.CallRequest) Call {
	id := model.NewId()
	callRequest.Variables[model.CALL_ID] = id
	callRequest.Variables[model.QUEUE_NODE_ID_FIELD] = cm.nodeId

	call := NewCall(callRequest, cm.callCommands)
	if call.Id() != "" {
		cm.SetCall(id, call)
	}
	return call
}

func (cm *CallManagerImpl) GetCall(id string) (Call, bool) {
	if call, ok := cm.calls.Get(id); ok {
		return call.(Call), true
	}
	return nil, false
}

func (cm *CallManagerImpl) SetCall(id string, call Call) {
	mlog.Debug(fmt.Sprintf("save store call %s %s", id, call.Id()))
	cm.calls.AddWithDefaultExpires(id, call)
}

func (cm *CallManagerImpl) RemoveCall(id string) {
	mlog.Debug(fmt.Sprintf("remove store call %s", id))
	cm.calls.Remove(id)
}
