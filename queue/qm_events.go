package queue

import (
	"fmt"
	"github.com/webitel/call_center/model"
)

func (queueManager *QueueManager) notifyStoppedResource(resource ResourceObject) {
	//TODO
}

func (queueManager *QueueManager) notifyChangedQueueLength(queue QueueObject) {
	//todo
	return

	res := <-queueManager.store.Member().ActiveCount(int64(queue.Id()))

	if res.Err != nil {
		panic(res.Err)
	}

	count, _ := res.Data.(int64)
	event := &model.QueueEventCount{
		QueueEvent: model.QueueEvent{
			Name:   model.QUEUE_EVENT_COUNT,
			Node:   queueManager.GetNodeId(),
			Domain: queue.Domain(),
		},
		Count: count,
	}

	if event != nil {

	}

	fmt.Println(count)
}
