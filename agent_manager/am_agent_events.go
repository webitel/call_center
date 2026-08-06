package agent_manager

import (
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
)

func logAgentStatusChange(agent AgentObject, status string) {
	agent.Log().Info(
		"agent changed status",
		wlog.String("agent_name", agent.Name()),
		wlog.Int("agent_id", agent.Id()),
		wlog.String("status", status),
	)
}

func NewAgentEventStatus(agent AgentObject, event model.AgentEventStatus) model.Event {
	logAgentStatusChange(agent, event.Status)

	return model.NewEvent(model.AgentChangedStatusEvent, agent.UserId(), event)
}

func NewAgentEventOnlineStatus(agent AgentObject, info *model.AgentOnlineData, onDemand bool) model.Event {
	logAgentStatusChange(agent, model.AgentStatusOnline)

	return model.NewEvent(
		model.AgentChangedStatusEvent,
		agent.UserId(),
		model.AgentEventOnlineStatus{
			Channels: info.Channel,
			OnDemand: onDemand,
			AgentEvent: model.AgentEvent{
				AgentId:   agent.Id(),
				UserId:    agent.UserId(),
				DomainId:  agent.DomainId(),
				Timestamp: info.Timestamp,
			},
			AgentStatus: model.CreateAgentStatus(model.AgentStatusOnline, model.WithStatusPreset(info.StatusPreset)),
		},
	)
}
