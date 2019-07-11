package queue

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
)

func (queueManager *QueueManager) notifyStoppedResource(resource ResourceObject) {
	//TODO
}

func (queueManager *QueueManager) notifyChangedQueueLength(queue QueueObject) {
	//TODO
	return
	count, err := queueManager.store.Member().ActiveCount(int64(queue.Id()))

	if err != nil {
		panic(err)
	}

	event := &model.QueueEventCount{
		QueueEvent: model.QueueEvent{
			Name:    model.QUEUE_EVENT_COUNT,
			Node:    queueManager.GetNodeId(),
			Time:    model.GetMillis(),
			Domain:  queue.Domain(),
			QueueId: int64(queue.Id()),
		},
		Count: count,
	}

	if err := queueManager.app.SendEventQueueChangedLength(event); err != nil {
		wlog.Error(err.Error())
	} else {
		wlog.Debug(fmt.Sprintf("queue %s[%d] changed length %d", queue.Name(), queue.Id(), count))
	}
}

func (queueManager *QueueManager) notifyStopAttempt(attempt *Attempt, stopped bool) {
	//fmt.Println(fmt.Sprintf("Stopped attempt %v", attempt.Id()))
}
