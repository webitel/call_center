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

func (queue *InboundQueue) DistributeAttempt(attempt *Attempt) {

	go func() {
		attempt.Log("wait agent")
		queue.queueManager.SetFindAgentState(attempt.Id())
		for {
			select {
			case <-attempt.timeout:
				info := queue.GetCallInfoFromAttempt(attempt)
				info.Timeout = true

				queue.StopAttemptWithCallDuration(attempt, model.MEMBER_CAUSE_ABANDONED, 0)

				attempt.Done()
			case agent := <-attempt.distributeAgent:
				attempt.Log(fmt.Sprintf("distribute agent %s [%d]", agent.Name(), agent.Id()))

				queue.queueManager.SetFindAgentState(attempt.Id())
				queue.queueManager.agentManager.SetAgentState(agent, model.AGENT_STATE_FINE, 1)

			case <-attempt.done:
				queue.queueManager.LeavingMember(attempt, queue)
				return
			}
		}
	}()
}
