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
	// todo timeout is deprecated
	if settings.MaxWaitTime == 0 {
		settings.MaxWaitTime = 60
	}

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

	attempt.memberChannel = mCall

	go queue.run(attempt, mCall)

	return nil
}

func (queue *InboundQueue) run(attempt *Attempt, mCall call_manager.Call) {
	var err *model.AppError
	defer attempt.Log("stopped queue")

	attempt.SetState(model.MemberStateJoined)
	attempt.Log("wait agent")
	if err = queue.queueManager.SetFindAgentState(attempt.Id()); err != nil {
		wlog.Error(err.Error())
		//todo
		return
	}

	attempt.SetState(model.MemberStateWaitAgent)

	attempts := 0

	var agent agent_manager.AgentObject
	var agentCall call_manager.Call
	var team *agentTeam

	var calling = mCall.HangupAt() == 0

	ags := attempt.On(AttemptHookDistributeAgent)

	//TODO
	timeout := time.NewTimer(time.Second * time.Duration(queue.props.MaxWaitTime))

	for calling {
		select {
		case <-timeout.C:
			calling = false
		case <-attempt.Context.Done():
			calling = false
		case <-attempt.Cancel():
			calling = false
		case c := <-mCall.State():
			if c == call_manager.CALL_STATE_HANGUP {
				if agentCall != nil && agentCall.BridgeAt() == 0 {
					team.MissedAgentAndWaitingAttempt(attempt, agent)
					attempt.SetState(model.MemberStateWaitAgent)
					if agentCall != nil && agentCall.HangupAt() == 0 {
						//TODO WaitForHangup
						//panic(agentCall.Id())
					}
					agent = nil
					agentCall = nil
					team = nil
				}

				calling = false
				break
			} else {
				wlog.Debug(fmt.Sprintf("[%d] change call state to %s", attempt.Id(), c))
			}

		case <-ags:
			agent = attempt.Agent()
			team, err = queue.GetTeam(attempt)
			if err != nil {
				wlog.Error(err.Error()) // todo
				time.Sleep(time.Second * 3)
				continue
			}
			attempt.Log(fmt.Sprintf("distribute agent %s [%d]", agent.Name(), agent.Id()))

			attempts++
			if mCall.HangupCause() != "" {
				attempt.Log(fmt.Sprintf("agent %s LOSE_RACE", agent.Name()))
				calling = false
				break
			}

			var apps []*model.CallRequestApplication

			apps = append(apps, &model.CallRequestApplication{
				AppName: "park",
				Args:    "",
			})

			cr := queue.AgentCallRequest(agent, team, attempt, apps)

			cr.Variables["wbt_parent_id"] = mCall.Id()

			// TODO DEV-3235
			delete(cr.Variables, "bridge_export_vars")

			agentCall = mCall.NewCall(cr)
			attempt.agentChannel = agentCall

			team.Distribute(queue, agent, NewDistributeEvent(attempt, agent.UserId(), queue, agent, queue.Processing(), mCall, agentCall))
			agentCall.Invite()

			wlog.Debug(fmt.Sprintf("call [%s] && agent [%s]", mCall.Id(), agentCall.Id()))

		top:
			for agentCall.HangupCause() == "" && (mCall.HangupCause() == "") {
				select {
				case <-attempt.Cancel():
					calling = false
				case state := <-agentCall.State():
					attempt.Log(fmt.Sprintf("agent call state %d", state))
					switch state {
					case call_manager.CALL_STATE_RINGING:
						attempt.Emit(AttemptHookOfferingAgent, agentCall.Id())
						team.Offering(attempt, agent, agentCall, mCall)

					case call_manager.CALL_STATE_ACCEPT:
						attempt.Emit(AttemptHookBridgedAgent, agentCall.Id())
						//FIXME
						result := AttemptResultSuccess
						if queue.Processing() {
							result = AttemptResultPostProcessing
						}
						mCall.SerVariables(map[string]string{
							"cc_result": result,
						})
						//
						time.Sleep(time.Millisecond * 250)
						if err = agentCall.Bridge(mCall); err != nil {
							if agentCall.HangupAt() == 0 {
								agentCall.Hangup(model.CALL_HANGUP_LOSE_RACE, false, nil)
							}
							printfIfErr(err)
						} else if mCall.Direction() == model.CallDirectionOutbound && attempt.state != model.MemberStateBridged {
							timeout.Stop()
							team.Bridged(attempt, agent)
						}

						//fixme refactor
						if queue.props.AllowGreetingAgent && agent.GreetingMedia() != nil {
							mCall.BroadcastPlaybackFile(agent.DomainId(), agent.GreetingMedia(), "both")
						} else if queue.AutoAnswer() {
							agentCall.BroadcastTone(queue.props.AutoAnswerTone, "aleg")
						}

					case call_manager.CALL_STATE_BRIDGE:
						if attempt.state != model.MemberStateBridged {
							timeout.Stop()
							team.Bridged(attempt, agent)
						}

					case call_manager.CALL_STATE_HANGUP:
						if agentCall.TransferTo() != nil && agentCall.TransferToAgentId() != nil && agentCall.TransferFromAttemptId() != nil {
							attempt.Log("receive transfer queue")
							if nc, err := queue.GetTransferredCall(*agentCall.TransferTo()); err != nil {
								wlog.Error(err.Error())
							} else {
								if nc.HangupAt() == 0 {
									if newA, err := queue.queueManager.TransferFrom(team, attempt, *agentCall.TransferFromAttemptId(),
										*agentCall.TransferToAgentId(), *agentCall.TransferTo(), nc); err == nil {
										agent = newA
										attempt.Log(fmt.Sprintf("transfer call from [%s] to [%s] AGENT_ID = %s {%d, %d}", agentCall.Id(), nc.Id(), newA.Name(), attempt.Id(), *agentCall.TransferFromAttemptId()))
									} else {
										wlog.Error(err.Error())
									}

									agentCall = nc
									continue
								}
							}
						}
						break top
					}
				case s := <-mCall.State():
					switch s {
					case call_manager.CALL_STATE_BRIDGE:
						timeout.Stop()
						team.Bridged(attempt, agent)
					case call_manager.CALL_STATE_HANGUP:
						attempt.Log(fmt.Sprintf("call hangup %s", mCall.Id()))

						if mCall.TransferToAttemptId() != nil {
							attempt.Log(fmt.Sprintf("transfer to %d, wait connect to attemt...", *mCall.TransferToAttemptId()))
							queue.queueManager.TransferTo(attempt, *mCall.TransferToAttemptId())
							return
						}

						if agentCall.HangupAt() == 0 {
							if mCall.BridgeAt() > 0 {
								agentCall.Hangup(model.CALL_HANGUP_NORMAL_CLEARING, false, nil)
							} else {
								agentCall.Hangup(model.CALL_HANGUP_ORIGINATOR_CANCEL, false, nil)
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
				attempt.SetState(model.MemberStateWaitAgent)
				if agentCall != nil && agentCall.HangupAt() == 0 {
					//TODO WaitForHangup
					//panic(agentCall.Id())
				}
				agent = nil
				agentCall = nil
				team = nil
			}

			calling = mCall.HangupAt() == 0 && mCall.BridgeAt() == 0
		}
	}

	if agentCall != nil && agentCall.HangupAt() == 0 {
		wlog.Warn(fmt.Sprintf("agent call %s no hangup", agentCall.Id()))
	}

	if agentCall != nil && agentCall.BridgeAt() > 0 {
		team.Reporting(queue, attempt, agent, agentCall.ReportingAt() > 0, agentCall.Transferred())
	} else if !queue.queueManager.SendAfterDistributeSchema(attempt) {
		queue.queueManager.Abandoned(attempt)
	}

	if mCall.HangupAt() == 0 && mCall.BridgeAt() == 0 {
		err = mCall.StopPlayback()
		if err != nil {
			wlog.Error(err.Error())
		}
	}

	go func() {
		attempt.Emit(AttemptHookLeaving)
		attempt.Off("*")
	}()
}
