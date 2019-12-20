package agent_manager

import "github.com/webitel/call_center/model"

func (cm *AgentManagerImpl) SetAgentWaiting(agentId int, bridged bool) *model.AppError {
	//FIXME EVENT
	return cm.store.Agent().SetWaiting(agentId, bridged)
}

func (cm *AgentManagerImpl) SetAgentOffering(agentId int) (int, *model.AppError) {
	//FIXME EVENT
	return cm.store.Agent().SetOffering(agentId)
}

func (cm *AgentManagerImpl) SetAgentTalking(agentId int) *model.AppError {
	//FIXME EVENT
	return cm.store.Agent().SetTalking(agentId)
}

func (cm *AgentManagerImpl) SetAgentReporting(agentId int, timeout int) *model.AppError {
	//FIXME EVENT
	return cm.store.Agent().SetReporting(agentId, timeout)
}

func (cm *AgentManagerImpl) SetAgentFine(agentId int, timeout int, noAnswer bool) *model.AppError {
	//FIXME EVENT
	return cm.store.Agent().SetFine(agentId, timeout, noAnswer)
}

func (cm *AgentManagerImpl) SetAgentOnBreak(agentId int) *model.AppError {
	return cm.store.Agent().SetOnBreak(agentId)
}
