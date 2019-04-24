package queue

import (
	"fmt"
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
)

func (queueManager *QueueManager) notifyStoppedResource(resource ResourceObject) {
	//TODO
}

func (queueManager *QueueManager) notifyChangedQueueLength(queue QueueObject) {
	//TODO
	return
	res := <-queueManager.store.Member().ActiveCount(int64(queue.Id()))

	if res.Err != nil {
		panic(res.Err)
	}

	count, _ := res.Data.(int64)
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
		mlog.Error(err.Error())
	} else {
		mlog.Debug(fmt.Sprintf("queue %s[%d] changed length %d", queue.Name(), queue.Id(), count))
	}
}

func (queueManager *QueueManager) notifyStopAttempt(attempt *Attempt, stopped bool) {
	fmt.Println(fmt.Sprintf("Stopped attempt %v", attempt.Id()))
}
