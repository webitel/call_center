package queue

import (
	"fmt"
	"github.com/webitel/call_center/model"
)

type InboundQueue struct {
	CallingQueue
}

func NewInboundQueue(callQueue CallingQueue, settings *model.Queue) QueueObject {
	return &InboundQueue{
		CallingQueue: callQueue,
	}
}

func (queue *InboundQueue) RouteAgentToAttempt(attempt *Attempt) {
	Assert(attempt.Agent())
	attempt.Log(fmt.Sprintf("distribute agent %s [%d]", attempt.Agent().Name(), attempt.Agent().Id()))
	//
	queue.queueManager.SetFindAgentState(attempt.Id())
	queue.queueManager.agentManager.SetAgentState(attempt.Agent(), model.AGENT_STATE_FINE, 1)
}

func (queue *InboundQueue) JoinAttempt(attempt *Attempt) {

	attempt.Info = &AttemptInfoCall{}

	err := queue.queueManager.SetAttemptState(attempt.Id(), model.MEMBER_STATE_FIND_AGENT)
	if err != nil {
		//TODO
		queue.StopAttemptWithCallDuration(attempt, model.MEMBER_CAUSE_ABANDONED, 0)
		queue.queueManager.LeavingMember(attempt, queue)
		return
	}
	attempt.Log("finding agent")
}

func (queue *InboundQueue) TimeoutAttempt(attempt *Attempt) {
	attempt.Log("timeout")
	info := queue.GetCallInfoFromAttempt(attempt)
	info.Timeout = true

	queue.StopAttemptWithCallDuration(attempt, model.MEMBER_CAUSE_ABANDONED, 0)
	queue.queueManager.LeavingMember(attempt, queue)
}
