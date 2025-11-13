package queue

import (
	"fmt"
	"time"

	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
)

type JoinAgentCallQueue struct {
	CallingQueue
}

func (queue *JoinAgentCallQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	mCall, ok := queue.CallManager().GetCall(*attempt.member.MemberCallId)
	if !ok {
		return NewErrorCallRequired(queue, attempt)
	}

	go queue.run(attempt, mCall)

	return nil
}

func (queue *JoinAgentCallQueue) run(attempt *Attempt, mCall call_manager.Call) {

	var calling = true
	var team *agentTeam
	var err *model.AppError

	defer attempt.Log("stopped queue")

	attempt.SetState(model.MemberStateJoined)

	agent := attempt.Agent()
	attempt.Log(fmt.Sprintf("distribute agent %s [%d]", agent.Name(), agent.Id()))

	team, err = queue.GetTeam(attempt)
	if err != nil {
		attempt.log.Error(err.Error(),
			wlog.Err(err),
		)
		//todo
		return
	}

	if mCall.HangupCause() != "" {
		attempt.Log(fmt.Sprintf("agent %s LOSE_RACE", agent.Name()))
		calling = false
	}

	var caller Caller = FlipCaller(mCall, agent, attempt)
	cr := queue.AgentCallRequest(agent, team, attempt, caller, []*model.CallRequestApplication{
		{
			AppName: "park",
			Args:    "",
		},
	})

	cr.Variables["wbt_parent_id"] = mCall.ParentOrId()

	agentCall := mCall.NewCall(cr)
	attempt.agentChannel = agentCall

	team.Distribute(queue, agent, NewDistributeEvent(attempt, agent.UserId(), queue, agent, queue.Processing(), mCall, agentCall))
	agentCall.Invite()

	attempt.log.Debug(fmt.Sprintf("call [%s] && agent [%s]", mCall.Id(), agentCall.Id()),
		wlog.Int("agent_id", agent.Id()),
		wlog.Int("team_id", agent.TeamId()),
		wlog.Int64("user_id", agent.UserId()),
	)

top:
	for calling && agentCall.HangupCause() == "" && (mCall.HangupCause() == "") {
		select {
		case state := <-agentCall.State():
			attempt.Log(fmt.Sprintf("agent call state %d", state))
			switch state {
			case call_manager.CALL_STATE_RINGING:
				team.Offering(attempt, agent, agentCall, mCall)

			case call_manager.CALL_STATE_ACCEPT:

				result := AttemptResultSuccess
				if queue.Processing() {
					result = AttemptResultPostProcessing
				}
				mCall.SerVariables(map[string]string{
					"cc_result": result,
				})

				if queue.bridgeSleep > 0 {
					time.Sleep(queue.bridgeSleep)
				}

				if err = agentCall.Bridge(mCall); err != nil {
					if agentCall.HangupAt() == 0 {
						agentCall.Hangup(model.CALL_HANGUP_LOSE_RACE, false, nil)
					}
				} else if !attempt.processTransfer && mCall.Direction() == model.CallDirectionOutbound && attempt.state != model.MemberStateBridged {
					team.Bridged(attempt, agent)
				}

			case call_manager.CALL_STATE_BRIDGE:
				if attempt.state != model.MemberStateBridged {
					team.Bridged(attempt, agent)
				}

			case call_manager.CALL_STATE_HANGUP:
				if agentCall.TransferTo() != nil && agentCall.TransferToAgentId() != nil && agentCall.TransferFromAttemptId() != nil {
					attempt.Log("receive transfer queue")
					if nc, err := queue.GetTransferredCall(*agentCall.TransferTo()); err != nil {
						attempt.log.Error(err.Error(),
							wlog.Err(err),
						)
					} else {
						if nc.HangupAt() == 0 {
							if newA, err := queue.queueManager.TransferFrom(team, attempt, *agentCall.TransferFromAttemptId(),
								*agentCall.TransferToAgentId(), *agentCall.TransferTo(), nc); err == nil {
								agent = newA
								attempt.Log(fmt.Sprintf("transfer call from [%s] to [%s] AGENT_ID = %s {%d, %d}", agentCall.Id(), nc.Id(), newA.Name(), attempt.Id(), *agentCall.TransferFromAttemptId()))
							} else {
								attempt.log.Error(err.Error(),
									wlog.Err(err),
								)
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
				if attempt.state != model.MemberStateBridged {
					team.Bridged(attempt, agent)
				}
			case call_manager.CALL_STATE_HANGUP:
				attempt.Log(fmt.Sprintf("call hangup %s", mCall.Id()))
				var tr CallTransfer
				mCall, tr = queue.transferResult(attempt, mCall)

				switch tr {
				case CallTransferForward:
					return
				case CallTransferSuccess:
					continue
				default:
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

	if agentCall != nil && agentCall.HangupAt() == 0 {
		attempt.log.Warn(fmt.Sprintf("agent call %s no hangup", agentCall.Id()))
	}

	if agentCall != nil && agentCall.BridgeAt() > 0 {
		team.Reporting(queue, attempt, agent, agentCall.ReportingAt() > 0, agentCall.Transferred())
	} else {
		mCall.StopPlayback()
		team.Missed(attempt, agent)
		queue.queueManager.LeavingMember(attempt)
	}

	go func() {
		attempt.Emit(AttemptHookLeaving)
		attempt.Off("*")
	}()
}
