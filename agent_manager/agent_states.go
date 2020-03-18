package agent_manager

import "github.com/webitel/call_center/model"

func (am *agentManager) SetAgentWaiting(agentId int, bridged bool) *model.AppError {
	//FIXME EVENT
	return am.store.Agent().SetWaiting(agentId, bridged)
}

func (am *agentManager) SetAgentOffering(agentId, queueId int) (int, *model.AppError) {
	//FIXME EVENT
	return am.store.Agent().SetOffering(agentId, queueId)
}

func (am *agentManager) SetAgentTalking(agentId int) *model.AppError {
	//FIXME EVENT
	return am.store.Agent().SetTalking(agentId)
}

func (am *agentManager) SetAgentReporting(agentId int, timeout int) *model.AppError {
	//FIXME EVENT
	return am.store.Agent().SetReporting(agentId, timeout)
}

func (am *agentManager) SetAgentFine(agentId int, timeout int, noAnswer bool) *model.AppError {
	//FIXME EVENT
	return am.store.Agent().SetFine(agentId, timeout, noAnswer)
}

func (am *agentManager) SetAgentOnBreak(agentId int) *model.AppError {
	return am.store.Agent().SetOnBreak(agentId)
}
