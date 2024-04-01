package queue

import (
	"fmt"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
	"time"
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
		wlog.Error(err.Error())
		//todo
		return
	}

	if mCall.HangupCause() != "" {
		attempt.Log(fmt.Sprintf("agent %s LOSE_RACE", agent.Name()))
		calling = false
	}

	cr := queue.AgentCallRequest(agent, team, attempt, []*model.CallRequestApplication{
		{
			AppName: "park",
			Args:    "",
		},
	})

	cr.Variables["wbt_parent_id"] = mCall.Id()

	agentCall := mCall.NewCall(cr)
	attempt.agentChannel = agentCall

	team.Distribute(queue, agent, NewDistributeEvent(attempt, agent.UserId(), queue, agent, queue.Processing(), mCall, agentCall))
	agentCall.Invite()

	wlog.Debug(fmt.Sprintf("call [%s] && agent [%s]", mCall.Id(), agentCall.Id()))

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
				//
				time.Sleep(time.Millisecond * 250)
				if err = agentCall.Bridge(mCall); err != nil {
					if agentCall.HangupAt() == 0 {
						agentCall.Hangup(model.CALL_HANGUP_LOSE_RACE, false, nil)
					}
				}

			case call_manager.CALL_STATE_BRIDGE:
				if attempt.state != model.MemberStateBridged {
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
				if attempt.state != model.MemberStateBridged {
					team.Bridged(attempt, agent)
				}
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

	if agentCall != nil && agentCall.HangupAt() == 0 {
		wlog.Warn(fmt.Sprintf("agent call %s no hangup", agentCall.Id()))
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
