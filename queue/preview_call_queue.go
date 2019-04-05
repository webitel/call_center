package queue

import (
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/model"
)

type PreviewCallQueue struct {
	CallingQueue
}

func NewPreviewCallQueue(callQueue CallingQueue) QueueObject {
	return &PreviewCallQueue{
		CallingQueue: callQueue,
	}
}

func (preview *PreviewCallQueue) RouteAgentToAttempt(attempt *Attempt, agent agent_manager.AgentObject) {
	//panic(`FoundAgentForAttempt queue not reserve agents`)
	fmt.Println(agent.CallDestination())
	preview.StopAttemptWithCallDuration(attempt, model.MEMBER_CAUSE_ABANDONED, 10)
	preview.queueManager.LeavingMember(attempt, preview)
}

func (preview *PreviewCallQueue) JoinAttempt(attempt *Attempt) {
	attempt.info = &AttemptInfoCall{}

	err := preview.queueManager.SetAttemptState(attempt.Id(), model.MEMBER_STATE_FIND_AGENT)
	if err != nil {
		//TODO
		preview.StopAttemptWithCallDuration(attempt, model.MEMBER_CAUSE_ABANDONED, 0)
		preview.queueManager.LeavingMember(attempt, preview)
		return
	}
}

func (preview *PreviewCallQueue) SetHangupCall(attempt *Attempt, event Event) {

}
