package agent_manager

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
)

func (am *agentManager) notifyChangeAgentState(agent AgentObject, state string) {
	//fmt.Println(agent)
}

func NewAgentEventStatus(agent AgentObject, status string, payload *string, timeout *int) model.AgentEventStatus {
	wlog.Info(fmt.Sprintf("agent %s[%d] has been changed state to \"%s\"", agent.Name(), agent.Id(), status))
	return model.AgentEventStatus{
		AgentEvent: model.AgentEvent{
			Event:     "status",
			AgentId:   agent.Id(),
			UserId:    agent.UserId(),
			DomainId:  agent.DomainId(),
			Timestamp: model.GetMillis(),
		},
		AgentStatus: model.AgentStatus{
			Status:        status,
			StatusPayload: payload,
		},
		Timeout: timeout,
	}
}
