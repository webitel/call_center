package queue

import (
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/mlog"
)

func (queueManager *QueueManager) StartListenEvents() {
	mlog.Debug("Starting queue listen events")
	defer func() {
		mlog.Debug("Stopped queue listener events")
	}()

	//for {
	//	select {
	//	case <-queueManager.stop:
	//		return
	//	case a, ok := <-queueManager.agentManager.ReservedAgentForAttempt():
	//		if !ok {
	//			return
	//		}
	//		queueManager.handleRouteAgentToQueue(a)
	//	}
	//}
}

func (queueManager *QueueManager) handleRouteAgentToQueue(a agent_manager.AgentInAttemptObject) {
	if attempt, ok := queueManager.membersCache.Get(a.AttemptId()); ok {

		if queue, err := queueManager.GetQueue(int(attempt.(*Attempt).QueueId()), attempt.(*Attempt).QueueUpdatedAt()); err == nil {
			attempt.(*Attempt).agent = a.Agent()
			queue.RouteAgentToAttempt(attempt.(*Attempt))
		} else {
			//todo not found queue
			mlog.Error(fmt.Sprintf("Not found queue AttemptId=%d for agent %s", a.AttemptId(), a.AgentName()))
		}
	} else {
		mlog.Error(fmt.Sprintf("Not found active attempt Id=%d for agent %s", a.AttemptId(), a.AgentName()))
	}
}
