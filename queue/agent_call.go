package queue

import (
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
)

func (queueManager *QueueManager) AgentReportingCall(agent agent_manager.AgentObject, call call_manager.Call) {
	var noAnswer = false
	var timeout = 0

	if call.Err() != nil {
		switch call.HangupCause() {
		case model.CALL_HANGUP_NO_ANSWER:
			noAnswer = true
			timeout = agent.NoAnswerDelayTime()
		case model.CALL_HANGUP_USER_BUSY:
			timeout = agent.BusyDelayTime()
		case model.CALL_HANGUP_REJECTED:
			timeout = agent.RejectDelayTime()
		}

		if result := <-queueManager.store.Agent().SaveActivityCallStatistic(agent.Id(), call.OfferingAt(), 0, 0, 0, noAnswer); result.Err != nil {
			//TODO
			mlog.Error(result.Err.Error())
		} else {
			if result.Data.(int64) == 1 {
				queueManager.agentManager.SetAgentStatus(agent, &model.AgentStatus{
					Status: model.AGENT_STATUS_PAUSE,
				})
			} else {
				queueManager.agentManager.SetAgentState(agent, model.AGENT_STATE_FINE, timeout)
			}
		}
	} else {
		if result := <-queueManager.store.Agent().SaveActivityCallStatistic(agent.Id(), call.OfferingAt(), call.AcceptAt(), call.BridgeAt(), call.HangupAt(), false); result.Err != nil {
			mlog.Error(result.Err.Error())
		}
		queueManager.agentManager.SetAgentState(agent, model.AGENT_STATE_REPORTING, int(agent.WrapUpTime()))
	}
}
