package agent_manager

import "github.com/webitel/call_center/model"

func (am *agentManager) notifyChangeAgentState(agent AgentObject, state string) {
	//fmt.Println(agent)
}

func NewAgentEventStatus(agent AgentObject, status string, payload *string, timeout *int) model.AgentEventStatus {
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
