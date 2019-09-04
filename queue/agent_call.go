package queue

import (
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
)

func (queueManager *QueueManager) AgentCallRequest(agent agent_manager.Agent) (*model.CallRequest, *model.AppError) {
	return nil, nil
}

func (queueManager *QueueManager) AgentReportingCall(team *agentTeam, agent agent_manager.AgentObject, call call_manager.Call) {
	var noAnswer = false
	var timeout = 0

	if call.Err() != nil {
		switch call.HangupCause() {
		case model.CALL_HANGUP_NO_ANSWER:
			noAnswer = true
			timeout = int(team.NoAnswerDelayTime())
		case model.CALL_HANGUP_REJECTED:
			timeout = int(team.RejectDelayTime())
		//case model.CALL_HANGUP_USER_BUSY:
		default:
			timeout = int(team.BusyDelayTime())
		}

		if cnt, err := queueManager.store.Agent().SaveActivityCallStatistic(agent.Id(), call.OfferingAt(), 0, 0, 0, noAnswer); err != nil {
			//TODO
			wlog.Error(err.Error())
		} else {
			if cnt == 1 {
				queueManager.agentManager.SetAgentStatus(agent, &model.AgentStatus{
					Status: model.AGENT_STATUS_PAUSE, // payload: max no answer
				})
			}

			if timeout == 0 {
				queueManager.agentManager.SetAgentState(agent, model.AGENT_STATE_WAITING, 0) // TODO
			} else {
				queueManager.agentManager.SetAgentState(agent, model.AGENT_STATE_FINE, timeout)
			}
		}
	} else {
		if _, err := queueManager.store.Agent().SaveActivityCallStatistic(agent.Id(), call.OfferingAt(), call.AcceptAt(), call.BridgeAt(), call.HangupAt(), false); err != nil {
			wlog.Error(err.Error())
		}
		if team.WrapUpTime() == 0 {
			queueManager.agentManager.SetAgentState(agent, model.AGENT_STATE_WAITING, 0)
		} else {
			queueManager.agentManager.SetAgentState(agent, model.AGENT_STATE_REPORTING, int(team.WrapUpTime()))
		}
	}
}
