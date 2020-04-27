package queue

import (
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
	"time"
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

func (queue *InboundQueue) reporting(attempt *Attempt, call, agentCall call_manager.Call, agent agent_manager.AgentObject, team *agentTeam) {
	attempt.SetState(model.MEMBER_STATE_POST_PROCESS)
	wlog.Debug(fmt.Sprintf("attempt[%d] start reporting", attempt.Id()))

	result := &model.AttemptResult{}
	result.Id = attempt.Id()
	if call != nil {
		result.LegAId = model.NewString(call.Id())
		result.OfferingAt = call.OfferingAt()
		result.AnsweredAt = call.AcceptAt()

		if call.BillSeconds() > 0 {
			result.Result = model.MEMBER_CAUSE_SUCCESSFUL
			result.BridgedAt = call.BridgeAt()
		} else {
			result.Result = model.MEMBER_CAUSE_ABANDONED
		}
		result.HangupAt = call.HangupAt()
	} else {
		result.HangupAt = model.GetMillis()
	}

	if agentCall != nil && agent != nil && team != nil {
		result.AgentId = model.NewInt(agent.Id())
		err := team.ReportingCall(&queue.CallingQueue, agent, agentCall, attempt)
		if err != nil {
			wlog.Error(err.Error())
		}
	}
	result.State = model.MEMBER_STATE_END

	attempt.SetResult(model.NewString(result.Result))

	//if err := queue.SetAttemptResult(result); err != nil {
	//	wlog.Error(fmt.Sprintf("attempt [%d] set result error: %s", attempt.Id(), err.Error()))
	//}

	close(attempt.distributeAgent)
	close(attempt.done)
	wlog.Debug(fmt.Sprintf("attempt[%d] reporting: %v", attempt.Id(), result))
	queue.queueManager.LeavingMember(attempt, queue)
}

type inboundQueueContext struct {
	attempt   *Attempt
	call      call_manager.Call
	agentCall call_manager.Call
	agent     agent_manager.AgentObject
	team      *agentTeam
}

func (queue *InboundQueue) run(attempt *Attempt) {
	var err *model.AppError
	var ok bool
	var call call_manager.Call
	var team *agentTeam

	call, ok = queue.CallManager().GetCall(*attempt.member.MemberCallId)
	if !ok {
		return
	}
	team, err = queue.GetTeam(attempt)
	if err != nil {
		//FIXME
		panic(err.Error())
	}

	defer attempt.Log("stopped queue")

	//TODO
	if attempt.member.Result != nil {
		return
	}

	attempt.Log("wait agent")
	if err = queue.queueManager.SetFindAgentState(attempt.Id()); err != nil {
		//FIXME
		panic(err.Error())
	}

	attempts := 0
	attempt.SetState(model.MEMBER_STATE_FIND_AGENT)

	timeout := time.NewTimer(time.Second * 5)

	var agent agent_manager.AgentObject
	var agentCall call_manager.Call

	for {
		select {
		case <-call.HangupChan():
			return

		case <-timeout.C:
			fmt.Println("TIMEOUT")

		case reason, ok := <-attempt.cancel:
			if !ok {
				continue //TODO
			}
			info := queue.GetCallInfoFromAttempt(attempt)

			attempt.SetResult(model.NewString(string(reason)))

			switch reason {
			case model.MEMBER_CAUSE_TIMEOUT:
				info.Timeout = true

			case model.MEMBER_CAUSE_CANCEL:
			default:
				//panic(reason)
			}
			return

		case agent = <-attempt.distributeAgent:
			attempts++
			if call.HangupCause() != "" {
				attempt.Log(fmt.Sprintf("agent %s LOSE_RACE", agent.Name()))
				continue
			}

			attempt.Log(fmt.Sprintf("distribute agent %s [%d]", agent.Name(), agent.Id()))
			attempt.SetState(model.MEMBER_STATE_PROGRESS)

			cr := queue.AgentCallRequest(agent, team, attempt)
			cr.Applications = []*model.CallRequestApplication{
				{
					AppName: "set",
					Args:    fmt.Sprintf("bridge_export_vars=%s,%s", model.QUEUE_AGENT_ID_FIELD, model.QUEUE_TEAM_ID_FIELD),
				},
				{
					AppName: "park",
				},
			}
			cr.Variables["wbt_parent_id"] = call.Id()

			if err = team.OfferingCall(queue, agent, attempt); err != nil {
				wlog.Error(err.Error())
			}
			agentCall = call.NewCall(cr)
			agentCall.Invite()

			wlog.Debug(fmt.Sprintf("call [%s] && agent [%s]", call.Id(), agentCall.Id()))

		top:
			for agentCall.HangupCause() == "" && call.HangupCause() == "" {
				select {
				case <-timeout.C:
					fmt.Println("TIMEOUT")
				case state := <-agentCall.State():
					attempt.Log(fmt.Sprintf("agent call state %d", state))
					switch state {
					case call_manager.CALL_STATE_ACCEPT:
						agentCall.Bridge(call)
						team.Talking(queue, agent, attempt)

					case call_manager.CALL_STATE_HANGUP:

						break top
					}
				case <-call.HangupChan():
					attempt.Log(fmt.Sprintf("call hangup %s", call.Id()))
					if agentCall.HangupAt() == 0 {
						if call.BridgeAt() > 0 {
							agentCall.Hangup(model.CALL_HANGUP_NORMAL_CLEARING, false)
						} else {
							agentCall.Hangup(model.CALL_HANGUP_ORIGINATOR_CANCEL, false)
						}
					}

					agentCall.WaitForHangup()
					attempt.Log(fmt.Sprintf("[%s] call %s receive hangup", agentCall.NodeName(), agentCall.Id()))
					break top
				}
			}

			if call.HangupCause() == "" && call.BridgeAt() == 0 {
				team.ReportingCall(&queue.CallingQueue, agent, agentCall, attempt)
				agentCall = nil
				agent = nil

				if queue.props.MaxCallPerAgent > 0 && attempts > queue.props.MaxCallPerAgent {
					attempt.cancel <- model.MEMBER_CAUSE_CANCEL
				} else {
					attempt.SetState(model.MEMBER_STATE_FIND_AGENT)
					queue.queueManager.SetFindAgentState(attempt.Id())
				}
			}

		case <-attempt.done:
			return
		}
	}
}
