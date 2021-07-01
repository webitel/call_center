package queue

import (
	"fmt"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
	"time"
)

type JoinAgentQueue struct {
	CallingQueue
}

func (queue *JoinAgentQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	mCall, ok := queue.CallManager().GetCall(*attempt.member.MemberCallId)
	if !ok {
		return NewErrorCallRequired(queue, attempt)
	}

	team, err := queue.GetTeam(attempt)
	if err != nil {
		return err
	}

	go queue.run(attempt, team, mCall)

	return nil
}

func (queue *JoinAgentQueue) run(attempt *Attempt, team *agentTeam, mCall call_manager.Call) {

	var calling = true

	defer attempt.Log("stopped queue")

	attempt.SetState(model.MemberStateJoined)

	agent := attempt.Agent()
	attempt.Log(fmt.Sprintf("distribute agent %s [%d]", agent.Name(), agent.Id()))

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
				attempt.Emit(AttemptHookBridgedAgent, agentCall.Id())
				//FIXME
				result := "success"
				if queue.Processing() {
					result = "processing"
				}
				mCall.SerVariables(map[string]string{
					"cc_result": result,
				})
				//
				time.Sleep(time.Millisecond * 250)
				printfIfErr(agentCall.Bridge(mCall))

			case call_manager.CALL_STATE_HANGUP:
				break top
			}
		case s := <-mCall.State():
			switch s {
			case call_manager.CALL_STATE_BRIDGE:
				team.Bridged(attempt, agent)
			case call_manager.CALL_STATE_HANGUP:
				attempt.Log(fmt.Sprintf("call hangup %s", mCall.Id()))
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
		team.Missed(attempt, agent)
		queue.queueManager.LeavingMember(attempt)
	}

	go func() {
		attempt.Emit(AttemptHookLeaving)
		attempt.Off("*")
	}()
}
