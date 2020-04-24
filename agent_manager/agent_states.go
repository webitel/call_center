package agent_manager

import "github.com/webitel/call_center/model"

func (am *agentManager) SetAgentWaiting(agent AgentObject, bridged bool) *model.AppError {
	//FIXME EVENT
	//am.mq.AgentChangeStatus(agent.DomainId(), agent.Id(), NewAgentEventStatus(agent, model.AGENT_STATE_WAITING, nil, nil))
	return am.store.Agent().SetWaiting(agent.Id(), bridged)
}

func (am *agentManager) SetAgentOffering(agent AgentObject, queueId int, attemptId int64) (int, *model.AppError) {
	//FIXME EVENT
	//am.mq.AgentChangeStatus(agent.DomainId(), agent.Id(), NewAgentEventStatus(agent, model.AGENT_STATE_OFFERING, nil, nil))
	return am.store.Agent().SetOffering(agent.Id(), queueId, attemptId)
}

func (am *agentManager) SetAgentTalking(agent AgentObject) *model.AppError {
	//FIXME EVENT
	//am.mq.AgentChangeStatus(agent.DomainId(), agent.Id(), NewAgentEventStatus(agent, model.AGENT_STATE_TALK, nil, nil))
	return am.store.Agent().SetTalking(agent.Id())
}

func (am *agentManager) SetAgentReporting(agent AgentObject, timeout int) *model.AppError {
	//FIXME EVENT
	//am.mq.AgentChangeStatus(agent.DomainId(), agent.Id(), NewAgentEventStatus(agent, model.AGENT_STATE_REPORTING, nil, nil))
	return am.store.Agent().SetReporting(agent.Id(), timeout)
}

func (am *agentManager) SetAgentFine(agent AgentObject, timeout int, noAnswer bool) *model.AppError {
	//FIXME EVENT
	//am.mq.AgentChangeStatus(agent.DomainId(), agent.Id(), NewAgentEventStatus(agent, model.AGENT_STATE_FINE, nil, &timeout))
	return am.store.Agent().SetFine(agent.Id(), timeout, noAnswer)
}

func (am *agentManager) SetAgentOnBreak(agentId int) *model.AppError {
	return am.store.Agent().SetOnBreak(agentId)
}
