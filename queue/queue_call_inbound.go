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
ringtone_id
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
	mCall, ok := queue.CallManager().GetCall(*attempt.member.MemberCallId)
	if !ok {
		return NewErrorCallRequired(queue, attempt)
	}

	team, err := queue.GetTeam(attempt)
	if err != nil {
		return err
	}

	go queue.run(attempt, mCall, team)

	return nil
}

func (queue *InboundQueue) run(attempt *Attempt, mCall call_manager.Call, team *agentTeam) {
	var err *model.AppError
	defer attempt.Log("stopped queue")

	attempt.Log("wait agent")
	if err = queue.queueManager.SetFindAgentState(attempt.Id()); err != nil {
		//FIXME
		panic(err.Error())
	}
	attempt.SetState(model.MemberStateWaitAgent)

	attempts := 0

	var agent agent_manager.AgentObject
	var agentCall call_manager.Call

	var calling = mCall.HangupAt() == 0

	ags := attempt.On(AttemptHookDistributeAgent)

	//TODO
	timeout := time.NewTimer(time.Second * time.Duration(queue.timeout))

	for calling {
		select {
		case <-timeout.C:
			calling = false
		case <-attempt.Context.Done():
			calling = false
		case c := <-mCall.State():
			if c == call_manager.CALL_STATE_HANGUP {
				calling = false
				break
			} else {
				wlog.Debug(fmt.Sprintf("[%d] change call state to %s", attempt.Id(), c))
			}

		case <-ags:
			agent = attempt.Agent()
			attempts++
			if mCall.HangupCause() != "" {
				attempt.Log(fmt.Sprintf("agent %s LOSE_RACE", agent.Name()))
				calling = false
				break
			}

			attempt.Log(fmt.Sprintf("distribute agent %s [%d]", agent.Name(), agent.Id()))

			cr := queue.AgentCallRequest(agent, team, attempt, []*model.CallRequestApplication{
				{
					AppName: "park",
					Args:    "",
				},
			})

			cr.Variables["wbt_parent_id"] = mCall.Id()

			agentCall = mCall.NewCall(cr)

			// fixme new function
			queue.Hook(agent, NewDistributeEvent(attempt, agent.UserId(), queue, agent, mCall, agentCall))
			team.Offering(attempt, agent, agentCall, mCall)
			agentCall.Invite()

			wlog.Debug(fmt.Sprintf("call [%s] && agent [%s]", mCall.Id(), agentCall.Id()))

		top:
			for agentCall.HangupCause() == "" && (mCall.HangupCause() == "") {
				select {
				case state := <-agentCall.State():
					attempt.Log(fmt.Sprintf("agent call state %d", state))
					switch state {
					case call_manager.CALL_STATE_ACCEPT:
						attempt.Emit(AttemptHookBridgedAgent, agentCall.Id())
						//FIXME
						result := "success"
						if team.PostProcessing() {
							result = "processing"
						}
						mCall.SerVariables(map[string]string{
							"cc_result": result,
						})
						//
						time.Sleep(time.Millisecond * 250)
						team.Answered(attempt, agent)
						printfIfErr(agentCall.Bridge(mCall))
						//fixme refactor
						if queue.props.AllowGreetingAgent {
							mCall.BroadcastPlaybackFile(agent.DomainId(), agent.GreetingMedia(), "both")
						}

					case call_manager.CALL_STATE_HANGUP:
						break top
					}
				case s := <-mCall.State():
					switch s {
					case call_manager.CALL_STATE_BRIDGE:
						timeout.Stop()
						team.Bridged(attempt, agent)
					case call_manager.CALL_STATE_HANGUP:
						attempt.Log(fmt.Sprintf("call hangup %s", mCall.Id()))
						if agentCall.HangupAt() == 0 {
							if mCall.BridgeAt() > 0 {
								agentCall.Hangup(model.CALL_HANGUP_NORMAL_CLEARING, false)
							} else {
								agentCall.Hangup(model.CALL_HANGUP_ORIGINATOR_CANCEL, false)
							}

							agentCall.WaitForHangup()
						}

						attempt.Log(fmt.Sprintf("[%s] agent call %s receive hangup", agentCall.NodeName(), agentCall.Id()))
						break top // FIXME
					}
				}
			}

			if agentCall.BridgeAt() == 0 {
				team.MissedAgentAndWaitingAttempt(attempt, agent)
				if agentCall != nil && agentCall.HangupAt() == 0 {
					//TODO WaitForHangup
					//panic(agentCall.Id())
				}
				agent = nil
				agentCall = nil
			}

			calling = mCall.HangupAt() == 0 && mCall.BridgeAt() == 0
		}
	}

	if agentCall != nil && agentCall.HangupAt() == 0 {
		wlog.Warn(fmt.Sprintf("agent call %s no hangup", agentCall.Id()))
	}

	if agentCall != nil && agentCall.BridgeAt() > 0 {
		team.Reporting(attempt, agent, agentCall.ReportingAt() > 0)
	} else {
		queue.queueManager.Abandoned(attempt)
	}

	go attempt.Emit(AttemptHookLeaving)
	go attempt.Off("*")
	queue.queueManager.LeavingMember(attempt, queue)
}
