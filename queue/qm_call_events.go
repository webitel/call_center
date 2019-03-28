package queue

import (
	"fmt"
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
)

func (queueManager *QueueManager) StartListenEvents() {
	mlog.Debug("Starting queue listen events")
	defer func() {
		mlog.Debug("Stopped queue listener events")
	}()

	for {
		select {
		case <-queueManager.stop:
			return
		case e, ok := <-queueManager.app.ConsumeCallEvent():
			if !ok {
				return
			}
			switch e.Name() {
			case model.CALL_EVENT_HANGUP:
				queueManager.handleCallHangup(e)
			case model.CALL_EVENT_ANSWER:

			}
		}
	}
}

func (queueManager *QueueManager) handleCallHangup(e mq.Event) {
	var ok bool
	var queue CallingQueueObject
	var attempt *Attempt

	if _, ok = e.GetVariable("grpc_originate_success"); !ok {
		mlog.Debug(fmt.Sprintf("Skip event %s [%s]", e.Name(), e.Id()))
		return
	}

	if queue, ok = queueManager.getCachedCallQueueFromEvent(e); !ok {
		return
	}

	if attempt, ok = queueManager.getCachedAttemptFromEvent(e); !ok {
		return
	}

	queue.SetHangupCall(attempt, e)
}

func (queueManager *QueueManager) getCachedCallQueueFromEvent(e mq.Event) (queue CallingQueueObject, ok bool) {
	var queueId int
	var _queue interface{}

	queueId, ok = e.GetIntVariable(model.QUEUE_ID_FIELD)
	if !ok {
		return
	}

	if _queue, ok = queueManager.queuesCache.Get(queueId); ok {
		queue = _queue.(CallingQueueObject)
	}
	return
}

func (queueManager *QueueManager) getCachedAttemptFromEvent(e mq.Event) (attempt *Attempt, ok bool) {
	var attemptId int
	var _attempt interface{}

	attemptId, ok = e.GetIntVariable(model.QUEUE_ATTEMPT_ID_FIELD)
	if !ok {
		return
	}

	if _attempt, ok = queueManager.membersCache.Get(int64(attemptId)); ok {
		attempt = _attempt.(*Attempt)
	}
	return
}
