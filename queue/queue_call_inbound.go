package queue

import (
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

func (voice *InboundQueue) RouteAgentToAttempt(attempt *Attempt) {
	Assert(attempt.Agent())
}

func (queue *InboundQueue) JoinAttempt(attempt *Attempt) {

}

func (queue *InboundQueue) TimeoutAttempt(attempt *Attempt) {

}
