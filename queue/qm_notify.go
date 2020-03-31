package queue

func (queueManager *QueueManager) notifyStoppedResource(resource ResourceObject) {
	//TODO
}

func (queueManager *QueueManager) notifyChangedQueueLength(queue QueueObject) {
	//TODO
	return

	//event := &model.QueueEventCount{
	//	QueueEvent: model.QueueEvent{
	//		Name:    model.QUEUE_EVENT_COUNT,
	//		Node:    queueManager.GetNodeId(),
	//		Time:    model.GetMillis(),
	//		Domain:  queue.Domain(),
	//		QueueId: int64(queue.Id()),
	//	},
	//	Count: count,
	//}

	//if err := queueManager.app.SendEventQueueChangedLength(event); err != nil {
	//	wlog.Error(err.Error())
	//} else {
	//	wlog.Debug(fmt.Sprintf("queue %s[%d] changed length %d", queue.Name(), queue.Id(), count))
	//}
}

func (queueManager *QueueManager) notifyStopAttempt(attempt *Attempt, stopped bool) {
	//fmt.Println(fmt.Sprintf("Stopped attempt %v", attempt.Id()))
}
