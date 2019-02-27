package dialing

import (
	"fmt"
	"github.com/webitel/call_center/model"
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
	fmt.Println("ADD NEW")
	//go func() {
	//	time.Sleep(time.Duration(rand.Intn(10000)) * time.Millisecond)
	//	voice.queueManager.LeavingMember(attempt, voice)
	//	voice.queueManager.SetAttemptError(attempt, model.MEMBER_STATE_END, model.MEMBER_CAUSE_ABANDONED)
	//}()
}
