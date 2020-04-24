package agent_manager

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
)

func (am *agentManager) notifyChangeAgentState(agent AgentObject, state string) {
	//fmt.Println(agent)
}

func NewAgentEventStatus(agent AgentObject, event model.AgentEventStatus) model.Event {
	wlog.Info(fmt.Sprintf("agent %s[%d] has been changed status to \"%s\"", agent.Name(), agent.Id(), event.Status))
	return model.NewEvent(model.AgentChangedStatusEvent, event)
}

func NewAgentEventOnlineStatus(agent AgentObject, info *model.AgentOnlineData, onDemand bool) model.Event {
	wlog.Info(fmt.Sprintf("agent %s[%d] has been changed status to \"%s\"", agent.Name(), agent.Id(), model.AgentStatusOnline))
	return model.NewEvent(model.AgentChangedStatusEvent, model.AgentEventOnlineStatus{
		Channels: info.Channels,
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
