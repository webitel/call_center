package queue

import (
	"fmt"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
)

/*
TODO: 1. можливо при _discard_abandoned_after брати максимально відалений ABANDONED

*/

type InboundQueue struct {
	CallingQueue
	props model.QueueInboundSettings
}

func NewInboundQueue(callQueue CallingQueue, settings model.QueueInboundSettings) QueueObject {
	return &InboundQueue{
		CallingQueue: callQueue,
		props:        settings,
	}
}

func (queue *InboundQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	go queue.run(attempt)
	return nil
}

func (queue *InboundQueue) reporting(attempt *Attempt) {
	info := queue.GetCallInfoFromAttempt(attempt)
	var result model.AttemptResult
	result.Id = attempt.Id()
	result.LegAId = model.NewString(info.fromCall.Id())

	if info.agent != nil {
		result.AgentId = model.NewInt(info.agent.Id())
		result.LegBId = model.NewString(info.toCall.Id())

		team, err := queue.GetTeam(attempt)
		if err != nil {
			//FIXME
		}
		team.ReportingCall(queue, info.agent, info.toCall)
	}

	result.OfferingAt = info.fromCall.OfferingAt()
	result.AnsweredAt = info.fromCall.AcceptAt()

	if info.fromCall.BillSeconds() > 0 {
		result.Result = model.MEMBER_CAUSE_SUCCESSFUL
		result.BridgedAt = info.fromCall.BridgeAt()
	} else {
		result.Result = model.MEMBER_CAUSE_ABANDONED
	}
	result.HangupAt = info.fromCall.HangupAt()
	result.State = model.MEMBER_STATE_END

	if err := queue.SetAttemptResult(&result); err != nil {
		wlog.Error(fmt.Sprintf("attempt [%d] set result error: %s", attempt.Id(), err.Error()))
	}

	queue.queueManager.LeavingMember(attempt, queue)
}

func (queue *InboundQueue) run(attempt *Attempt) {

	info := queue.GetCallInfoFromAttempt(attempt)
	defer queue.reporting(attempt)

	call, ok := queue.CallManager().GetCall(*attempt.member.CallFromId)
	info.fromCall = call

	team, err := queue.GetTeam(attempt)
	if err != nil {
		//FIXME
	}

	if !ok {
		attempt.Log("not found active call")
		return
	}

	defer attempt.Log("stopped queue")
	defer close(attempt.distributeAgent)

	//TODO
	if attempt.member.Result != nil {
		return
	}

	attempt.Log("wait agent")
	queue.queueManager.SetFindAgentState(attempt.Id())

	for {
		select {
		case <-call.HangupChan():
			return

		case reason, ok := <-attempt.cancel:
			if !ok {
				continue //TODO
			}
			info := queue.GetCallInfoFromAttempt(attempt)

			switch reason {
			case model.MEMBER_CAUSE_TIMEOUT:
				info.Timeout = true

			case model.MEMBER_CAUSE_CANCEL:
			default:
				panic(reason)
			}
			return

		case agent := <-attempt.distributeAgent:

			if call.HangupCause() != "" {
				attempt.Log(fmt.Sprintf("agent %s LOSE_RACE", agent.Name()))
				continue
			}

			attempt.Log(fmt.Sprintf("distribute agent %s [%d]", agent.Name(), agent.Id()))

			info.agent = agent

			cr := queue.AgentCallRequest(agent, team, attempt)
			cr.Applications = []*model.CallRequestApplication{
				{
					AppName: "set",
					Args:    fmt.Sprintf("bridge_export_vars=%s,%s", model.QUEUE_AGENT_ID_FIELD, model.QUEUE_TEAM_ID_FIELD),
				},
				{
					AppName: "valet_park",
					Args:    fmt.Sprintf("queue_%d %s", queue.Id(), call.Id()),
				},
			}

			team.OfferingCall(queue, agent, attempt)
			agentCall := call.NewCall(cr)
			agentCall.Invite()

			info.toCall = agentCall

			wlog.Debug(fmt.Sprintf("call [%s] && agent [%s]", call.Id(), agentCall.Id()))

		top:
			for agentCall.HangupCause() == "" && call.HangupCause() == "" {
				select {
				case state := <-agentCall.State():
					switch state {
					case call_manager.CALL_STATE_ACCEPT:
						team.Talking(queue, agent, attempt)

					case call_manager.CALL_STATE_HANGUP:

						break top
					}
				case <-call.HangupChan():
					if agentCall.HangupAt() == 0 {
						if call.BridgeAt() > 0 {
							agentCall.Hangup(model.CALL_HANGUP_NORMAL_CLEARING)
						} else {
							agentCall.Hangup(model.CALL_HANGUP_ORIGINATOR_CANCEL)
						}
					}

					agentCall.WaitForHangup()
					wlog.Debug(fmt.Sprintf("[%s] call %s receive hangup", agentCall.NodeName(), agentCall.Id()))
					break top
				}
			}

			if call.HangupCause() == "" && call.BridgeAt() == 0 {
				//FIXME store missed CC agent calls
				team.ReportingCall(queue, agent, agentCall)
				queue.queueManager.SetFindAgentState(attempt.Id())
				info.toCall = nil
			}

		case <-attempt.done:
			return
		}
	}
}
