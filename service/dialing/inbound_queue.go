package dialing

import (
	"fmt"
	"github.com/webitel/call_center/model"
)

type InboundQueue struct {
	BaseQueue
}

func NewInboundQueue(baseQueue BaseQueue, settings *model.Queue) QueueObject {
	return &InboundQueue{
		BaseQueue: baseQueue,
	}
}

func (queue *InboundQueue) AddMemberAttempt(attempt *Attempt) {
	fmt.Println(attempt)
}
