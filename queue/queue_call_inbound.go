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

func stopInboundAttempt(queue *InboundQueue, attempt *Attempt) {
	queue.StopAttemptWithCallDuration(attempt, model.MEMBER_CAUSE_ABANDONED, 0)
	queue.queueManager.LeavingMember(attempt, queue)
	return
}

func (queue *InboundQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	go queue.run(attempt)
	return nil
}

func (queue *InboundQueue) run(attempt *Attempt) {

	info := queue.GetCallInfoFromAttempt(attempt)

	call, ok := queue.CallManager().GetCall(*attempt.member.CallFromId)
	info.fromCall = call

	team, err := queue.GetTeam(attempt)
	if err != nil {
		//FIXME
	}

	if !ok {
		attempt.Log("not found active call")
		queue.StopAttemptWithCallDuration(attempt, model.MEMBER_CAUSE_ABANDONED, 0)
		queue.queueManager.LeavingMember(attempt, queue)
		return
	}

	defer attempt.Log("stopped queue")
	defer close(attempt.distributeAgent)

	//TODO
	if attempt.member.Result != nil {
		queue.StopAttemptWithCallDuration(attempt, model.MEMBER_CAUSE_ABANDONED, 0)
		queue.queueManager.LeavingMember(attempt, queue)
		return
	}

	attempt.Log("wait agent")
	queue.queueManager.SetFindAgentState(attempt.Id())

	for {
		select {
		case <-call.HangupChan():
			stopInboundAttempt(queue, attempt)
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
			stopInboundAttempt(queue, attempt)
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
					AppName: "answer",
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
						call.Bridge(agentCall)

					case call_manager.CALL_STATE_HANGUP:
						break top
					}
				case <-call.HangupChan():
					if call.BridgeAt() > 0 {
						agentCall.Hangup(model.CALL_HANGUP_NORMAL_CLEARING)
					} else {
						agentCall.Hangup(model.CALL_HANGUP_ORIGINATOR_CANCEL)
					}

					agentCall.WaitForHangup()
					wlog.Debug(fmt.Sprintf("[%s] call %s receive hangup", agentCall.NodeName(), agentCall.Id()))
					break top
				}
			}

			team.ReportingCall(queue, agent, agentCall)

			if call.HangupCause() == "" && call.BridgeAt() == 0 {
				//FIXME store missed CC agent calls
				queue.queueManager.SetFindAgentState(attempt.Id())
			}

		case <-attempt.done:

			queue.StopAttemptWithCallDuration(attempt, model.MEMBER_CAUSE_ABANDONED, 0)
			queue.queueManager.LeavingMember(attempt, queue)
			return
		}
	}
}
