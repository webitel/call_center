package queue

import (
	"fmt"
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
	"math/rand"
	"time"
)

type InboundQueue struct {
	CallingQueue
}

func NewInboundQueue(callQueue CallingQueue, settings *model.Queue) QueueObject {
	return &InboundQueue{
		CallingQueue: callQueue,
	}
}

func (voice *InboundQueue) FoundAgentForAttempt(attempt *Attempt) {
	fmt.Println("OK-TODO")
}

func (queue *InboundQueue) AddMemberAttempt(attempt *Attempt) {
	err := queue.queueManager.SetAttemptState(attempt.Id(), model.MEMBER_STATE_FIND_AGENT)
	if err != nil {
		panic(err.Error())
	}
	mlog.Debug(fmt.Sprintf("Check agent for member %v in queue %v", attempt.Name(), queue.Name()))

	go func() {
		time.Sleep(time.Duration(rand.Intn(10000)+1000) * time.Millisecond)
		queue.queueManager.SetAttemptError(attempt, model.MEMBER_STATE_END, model.MEMBER_CAUSE_ABANDONED)
		queue.queueManager.LeavingMember(attempt, queue)
	}()
}

func (voice *InboundQueue) SetHangupCall(attempt *Attempt) {

}
