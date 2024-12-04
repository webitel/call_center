package agent_manager

import (
	"fmt"
	"github.com/webitel/call_center/model"
)

func NewAgentEventStatus(agent AgentObject, event model.AgentEventStatus) model.Event {
	agent.Log().Info(fmt.Sprintf("agent %s[%d] has been changed status to \"%s\"", agent.Name(), agent.Id(), event.Status))
	return model.NewEvent(model.AgentChangedStatusEvent, agent.UserId(), event)
}

func NewAgentEventOnlineStatus(agent AgentObject, info *model.AgentOnlineData, onDemand bool) model.Event {
	agent.Log().Info(fmt.Sprintf("agent %s[%d] has been changed status to \"%s\"", agent.Name(), agent.Id(), model.AgentStatusOnline))
	return model.NewEvent(model.AgentChangedStatusEvent, agent.UserId(), model.AgentEventOnlineStatus{
		Channels: info.Channel,
		OnDemand: onDemand,
		AgentEvent: model.AgentEvent{
			AgentId:   agent.Id(),
			UserId:    agent.UserId(),
			DomainId:  agent.DomainId(),
			Timestamp: info.Timestamp,
		},
		AgentStatus: model.AgentStatus{
			Status: model.AgentStatusOnline,
		},
	})
}
