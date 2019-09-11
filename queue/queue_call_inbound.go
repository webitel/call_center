package queue

import (
	"fmt"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
)

type InboundQueue struct {
	CallingQueue
}

func NewInboundQueue(callQueue CallingQueue, settings *model.Queue) QueueObject {
	return &InboundQueue{
		CallingQueue: callQueue,
	}
}

func stopInboundAttempt(queue *InboundQueue, attempt *Attempt) {
	queue.StopAttemptWithCallDuration(attempt, model.MEMBER_CAUSE_ABANDONED, 0)
	queue.queueManager.LeavingMember(attempt, queue)
	return
}

func (queue *InboundQueue) DistributeAttempt(attempt *Attempt) *model.AppError {

	go func() {
		info := queue.GetCallInfoFromAttempt(attempt)

		call, ok := queue.CallManager().GetCall(*attempt.member.CallFromId)
		info.fromCall = call

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

		defer func() {
			if info.agent != nil {
				info.agent.SetStateReporting(10)
			}
		}()
		//originate {sip_route_uri=sip:192.168.177.13,sip_h_X-Webitel-Direction=outbound}sofia/sip/agent@10.10.10.200:5080 &sleep(1
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
				agent.SetStateOffering(0)

				agentCall := call.NewCall(&model.CallRequest{
					Endpoints: agent.GetCallEndpoints(), //[]string{`sofia/sip/agent@10.10.10.200:5080`} []string{`loopback/answer\,park/default/inline`}, ///agent.GetCallEndpoints(),
					Strategy:  model.CALL_STRATEGY_DEFAULT,
					Variables: model.UnionStringMaps(
						queue.Variables(),
						attempt.Variables(),
						map[string]string{
							"sip_route_uri":                        queue.SipRouterAddr(),
							"sip_h_X-Webitel-Direction":            "internal",
							"other_loopback_leg_uuid":              model.NewUuid(),
							"absolute_codec_string":                "PCMU",
							"valet_hold_music":                     "silence",
							model.CALL_IGNORE_EARLY_MEDIA_VARIABLE: "true",
							model.CALL_DIRECTION_VARIABLE:          model.CALL_DIRECTION_DIALER,
							model.CALL_DOMAIN_VARIABLE:             queue.Domain(),
							model.QUEUE_ID_FIELD:                   fmt.Sprintf("%d", queue.id),
							model.QUEUE_NAME_FIELD:                 queue.name,
							model.QUEUE_TYPE_NAME_FIELD:            queue.TypeName(),
							model.QUEUE_SIDE_FIELD:                 model.QUEUE_SIDE_AGENT,
							model.QUEUE_MEMBER_ID_FIELD:            fmt.Sprintf("%d", attempt.MemberId()),
							model.QUEUE_ATTEMPT_ID_FIELD:           fmt.Sprintf("%d", attempt.Id()),
						},
					),
					Timeout:      60,
					CallerName:   attempt.Name(),
					CallerNumber: attempt.Destination(),
					Applications: []*model.CallRequestApplication{
						{
							AppName: "valet_park",
							Args:    fmt.Sprintf("queue_%d %s", queue.Id(), call.Id()),
						},
					},
				})

				agentCall.Invite()

				wlog.Debug(fmt.Sprintf("call [%s] && agent [%s]", call.Id(), agentCall.Id()))

			top:
				for agentCall.HangupCause() == "" && call.HangupCause() == "" {
					select {
					case state := <-agentCall.State():
						switch state {
						case call_manager.CALL_STATE_ACCEPT:
							agent.SetStateTalking(0)

						case call_manager.CALL_STATE_HANGUP:
							break top
						}
					case <-call.HangupChan():
						agentCall.Hangup(model.CALL_HANGUP_ORIGINATOR_CANCEL)
						agentCall.WaitForHangup()
						wlog.Debug(fmt.Sprintf("[%s] call %s receive hangup", agentCall.NodeName(), agentCall.Id()))
						break top
					}
				}

				if call.BridgeAt() > 0 {
					agent.SetStateReporting(5)
				} else {
					agent.SetStateFine(5)
					queue.queueManager.SetFindAgentState(attempt.Id())
				}

			case <-attempt.done:

				queue.StopAttemptWithCallDuration(attempt, model.MEMBER_CAUSE_ABANDONED, 0)
				queue.queueManager.LeavingMember(attempt, queue)
				return
			}
		}
	}()

	return nil
}
