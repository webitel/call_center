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
		defer attempt.Log("stopped queue")

		//TODO
		if attempt.member.Result != nil {
			queue.StopAttemptWithCallDuration(attempt, model.MEMBER_CAUSE_ABANDONED, 0)
			queue.queueManager.LeavingMember(attempt, queue)
			return
		} else {
			queue.queueManager.SetFindAgentState(attempt.Id())
		}
		for {
			select {
			case reason, ok := <-attempt.cancel:
				if !ok {
					continue //
				}
				info := queue.GetCallInfoFromAttempt(attempt)

				switch reason {
				case model.MEMBER_CAUSE_TIMEOUT:
					info.Timeout = true

				case model.MEMBER_CAUSE_CANCEL:
				default:
					panic(reason)
				}

				attempt.Done()

			case agent := <-attempt.distributeAgent:
				attempt.Log(fmt.Sprintf("distribute agent %s [%d]", agent.Name(), agent.Id()))

				queue.queueManager.agentManager.SetAgentState(agent, model.AGENT_STATE_FINE, 10)
				//time.Sleep(time.Second * 5)
				queue.queueManager.SetFindAgentState(attempt.Id())

			case <-attempt.done:
				queue.StopAttemptWithCallDuration(attempt, model.MEMBER_CAUSE_ABANDONED, 0)
				queue.queueManager.LeavingMember(attempt, queue)
				return
			}
		}
	}()
}
