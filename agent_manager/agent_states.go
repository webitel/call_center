package agent_manager

import "github.com/webitel/call_center/model"

func (am *agentManager) SetAgentOnBreak(agentId int) *model.AppError {
	return am.store.Agent().SetOnBreak(agentId)
}
