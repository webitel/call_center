package dialing

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"time"
)

type VoiceBroadcastQueue struct {
	BaseQueue
}

func NewVoiceBroadcastQueue(baseQueue BaseQueue, settings *model.Queue) QueueObject {
	return &VoiceBroadcastQueue{
		BaseQueue: baseQueue,
	}
}

func (voice *VoiceBroadcastQueue) AddMemberAttempt(attempt *Attempt) {
	if attempt.member.ResourceId == nil || attempt.member.ResourceUpdatedAt == nil {
		panic(123)
	}

	r, e := voice.resourceManager.Get(*attempt.member.ResourceId, *attempt.member.ResourceUpdatedAt)
	if e != nil {
		panic(e.Error())
	}

	go func() {

		fmt.Println(r.GetDialString())
		time.Sleep(time.Duration(5000) * time.Millisecond)
		voice.queueManager.LeavingMember(attempt, voice)
		voice.queueManager.SetAttemptError(attempt, model.MEMBER_STATE_END, model.MEMBER_CAUSE_ABANDONED)
	}()
}
