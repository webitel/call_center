package queue

import (
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
)

func (queue *CallingQueue) AgentCallRequest(agent agent_manager.AgentObject, at *agentTeam, attempt *Attempt) *model.CallRequest {
	cr := &model.CallRequest{
		Endpoints:   agent.GetCallEndpoints(),
		Strategy:    model.CALL_STRATEGY_DEFAULT,
		Destination: attempt.Destination(),
		Variables: model.UnionStringMaps(
			queue.Variables(),
			attempt.Variables(),
			map[string]string{
				//"bridge_export_vars":                   "",
				"sip_h_X-Webitel-Direction":  "internal",
				model.QUEUE_TEAM_ID_FIELD:    fmt.Sprintf("%d", at.Id()),
				model.QUEUE_ID_FIELD:         fmt.Sprintf("%d", queue.Id()),
				model.QUEUE_NAME_FIELD:       queue.Name(),
				model.QUEUE_TYPE_NAME_FIELD:  queue.TypeName(),
				model.QUEUE_SIDE_FIELD:       model.QUEUE_SIDE_AGENT,
				model.QUEUE_MEMBER_ID_FIELD:  fmt.Sprintf("%d", attempt.MemberId()),
				model.QUEUE_ATTEMPT_ID_FIELD: fmt.Sprintf("%d", attempt.Id()),
			},
		),
		Timeout:      at.CallTimeout(),
		CallerName:   attempt.Name(),
		CallerNumber: attempt.Destination(),
	}
	return cr
}

func (queue *CallingQueue) AgentReportingCall(team *agentTeam, agent agent_manager.AgentObject, call call_manager.Call) {
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

		if noAnswer {
		}

		agent.SetStateFine(timeout, noAnswer)
	} else {
		agent.SetStateReporting(int(team.WrapUpTime()))
	}

	//	if cnt, err := queue.SaveAgentActivityCallStatistic(agent.Id(), call.OfferingAt(), 0, 0, 0, noAnswer); err != nil {
	//		//TODO
	//		wlog.Error(err.Error())
	//	} else {
	//		if cnt == 1 {
	//			queue.AgentManager().SetAgentStatus(agent, &model.AgentStatus{
	//				Status: model.AGENT_STATUS_PAUSE, // payload: max no answer
	//			})
	//		}
	//
	//		if timeout == 0 {
	//			queue.AgentManager().SetAgentState(agent, model.AGENT_STATE_WAITING, 0) // TODO
	//		} else {
	//			queue.AgentManager().SetAgentState(agent, model.AGENT_STATE_FINE, timeout)
	//		}
	//	}
	//} else {
	//	if _, err := queue.SaveAgentActivityCallStatistic(agent.Id(), call.OfferingAt(), call.AcceptAt(), call.BridgeAt(), call.HangupAt(), false); err != nil {
	//		wlog.Error(err.Error())
	//	}
	//	if team.WrapUpTime() == 0 {
	//		queue.AgentManager().SetAgentState(agent, model.AGENT_STATE_WAITING, 0)
	//	} else {
	//		queue.AgentManager().SetAgentState(agent, model.AGENT_STATE_REPORTING, int(team.WrapUpTime()))
	//	}
	//}
}
