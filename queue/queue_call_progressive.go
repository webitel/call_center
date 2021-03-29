package queue

import (
	"encoding/json"
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
	"time"
)

type ProgressiveCallQueue struct {
	CallingQueue
	ProgressiveCallQueueSettings
}

type ProgressiveCallQueueSettings struct {
	Recordings         bool   `json:"recordings"`
	WaitBetweenRetries int    `json:"wait_between_retries"`
	MaxAttempts        int    `json:"max_attempts"`
	OriginateTimeout   uint16 `json:"originate_timeout"`
	AllowGreetingAgent bool   `json:"allow_greeting_agent"`
	Amd                *model.QueueAmdSettings
}

func ProgressiveSettingsFromBytes(data []byte) ProgressiveCallQueueSettings {
	var settings ProgressiveCallQueueSettings
	json.Unmarshal(data, &settings)
	return settings
}

func NewProgressiveCallQueue(callQueue CallingQueue, settings ProgressiveCallQueueSettings) QueueObject {
	return &ProgressiveCallQueue{
		CallingQueue:                 callQueue,
		ProgressiveCallQueueSettings: settings,
	}
}

func (queue *ProgressiveCallQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	if attempt.resource == nil {
		return NewErrorResourceRequired(queue, attempt)
	}

	if attempt.agent == nil {
		return NewErrorAgentRequired(queue, attempt)
	}

	team, err := queue.GetTeam(attempt)
	if err != nil {
		return err
	}

	go queue.run(attempt, team, attempt.Agent())

	return nil
}

// bug agent number
func (queue *ProgressiveCallQueue) run(attempt *Attempt, team *agentTeam, agent agent_manager.AgentObject) {

	if !queue.queueManager.DoDistributeSchema(&queue.BaseQueue, attempt) {
		queue.queueManager.LeavingMember(attempt)
		return
	}

	dst := attempt.resource.Gateway().Endpoint(attempt.Destination())
	var callerIdNumber string

	// FIXME display
	if attempt.communication.Display != nil && *attempt.communication.Display != "" {
		callerIdNumber = *attempt.communication.Display
	} else {
		callerIdNumber = attempt.resource.GetDisplay()
	}

	callRequest := &model.CallRequest{
		Id:           attempt.MemberCallId(),
		Endpoints:    []string{dst},
		CallerNumber: attempt.Destination(),
		CallerName:   attempt.Name(),
		Timeout:      queue.OriginateTimeout,
		Destination:  attempt.Destination(),
		Variables: model.UnionStringMaps(
			queue.Variables(),
			attempt.ExportVariables(),
			map[string]string{
				model.CallVariableDomainName: queue.Domain(),
				model.CallVariableDomainId:   fmt.Sprintf("%v", queue.DomainId()),
				model.CallVariableGatewayId:  fmt.Sprintf("%v", attempt.resource.Gateway().Id),

				"hangup_after_bridge":    "true",
				"ignore_display_updates": "true",

				"sip_h_X-Webitel-Display-Direction": "outbound",
				"sip_h_X-Webitel-Origin":            "request",
				"wbt_destination":                   attempt.Destination(),
				"wbt_from_id":                       fmt.Sprintf("%v", attempt.resource.Gateway().Id), //FIXME gateway id ?
				"wbt_from_number":                   callerIdNumber,
				"wbt_from_name":                     attempt.resource.Gateway().Name,
				"wbt_from_type":                     "gateway",

				"wbt_to_id":     fmt.Sprintf("%d", *attempt.MemberId()),
				"wbt_to_name":   attempt.Name(),
				"wbt_to_type":   "member",
				"wbt_to_number": attempt.Destination(),

				"effective_caller_id_number": callerIdNumber,
				"effective_caller_id_name":   attempt.resource.Name(),

				"effective_callee_id_name":   attempt.Name(),
				"effective_callee_id_number": attempt.Destination(),

				"origination_caller_id_name":   attempt.resource.Name(),
				"origination_caller_id_number": callerIdNumber,
				"origination_callee_id_name":   attempt.Name(),
				"origination_callee_id_number": attempt.Destination(),

				model.QUEUE_ID_FIELD:        fmt.Sprintf("%d", queue.Id()),
				model.QUEUE_NAME_FIELD:      queue.Name(),
				model.QUEUE_TYPE_NAME_FIELD: queue.TypeName(),

				model.QUEUE_SIDE_FIELD:        model.QUEUE_SIDE_MEMBER,
				model.QUEUE_MEMBER_ID_FIELD:   fmt.Sprintf("%v", *attempt.MemberId()),
				model.QUEUE_ATTEMPT_ID_FIELD:  fmt.Sprintf("%d", attempt.Id()),
				model.QUEUE_RESOURCE_ID_FIELD: fmt.Sprintf("%d", attempt.resource.Id()),
			},
		),
		Applications: make([]*model.CallRequestApplication, 0, 2),
	}

	mCall := queue.NewCallUseResource(callRequest, attempt.resource)
	var agentCall call_manager.Call

	if queue.Recordings {
		callRequest.Applications = append(callRequest.Applications, queue.GetRecordingsApplication(mCall))
	}

	if !queue.SetAmdCall(callRequest, queue.Amd, "park") {
		callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
			AppName: "park",
		})
	}

	//FIXME update member call id
	team.Distribute(queue, agent, NewDistributeEvent(attempt, agent.UserId(), queue, agent, queue.Processing(), nil, mCall))
	mCall.Invite()

	var calling = true

	for calling {
		select {
		case state := <-mCall.State():
			switch state {
			case call_manager.CALL_STATE_ACCEPT, call_manager.CALL_STATE_DETECT_AMD:
				// FIXME
				if (state == call_manager.CALL_STATE_ACCEPT && queue.Amd != nil && queue.Amd.Enabled) || (state == call_manager.CALL_STATE_DETECT_AMD && !mCall.IsHuman()) {
					continue
				}

				if cnt, err := queue.queueManager.store.Agent().ConfirmAttempt(agent.Id(), attempt.Id()); err != nil || len(cnt) == 0 {
					mCall.Hangup(model.CALL_HANGUP_ORIGINATOR_CANCEL, false)
				} else if len(cnt) > 0 {

					go queue.HangupManyCall(mCall.Id(), model.CALL_HANGUP_ORIGINATOR_CANCEL, cnt...)

					cr := queue.AgentCallRequest(agent, team, attempt, []*model.CallRequestApplication{
						{
							AppName: "set",
							Args:    fmt.Sprintf("bridge_export_vars=%s,%s", model.QUEUE_AGENT_ID_FIELD, model.QUEUE_TEAM_ID_FIELD),
						},
						{
							AppName: "park",
						},
					})
					cr.Variables["wbt_parent_id"] = mCall.Id()
					agentCall = mCall.NewCall(cr)
					printfIfErr(agentCall.Invite())

					wlog.Debug(fmt.Sprintf("call [%s] && agent [%s]", mCall.Id(), agentCall.Id()))

				top:
					for agentCall.HangupCause() == "" && mCall.HangupCause() == "" {
						select {
						case state := <-agentCall.State():
							attempt.Log(fmt.Sprintf("agent call state %d", state))
							switch state {
							case call_manager.CALL_STATE_RINGING:
								team.Offering(attempt, agent, agentCall, mCall)

							case call_manager.CALL_STATE_ACCEPT:
								time.Sleep(time.Millisecond * 250)
								printfIfErr(agentCall.Bridge(mCall)) // TODO
								//fixme refactor
								if queue.AllowGreetingAgent {
									mCall.BroadcastPlaybackFile(agent.DomainId(), agent.GreetingMedia(), "both")
								}

								//team.Answered(attempt, agent)
							case call_manager.CALL_STATE_HANGUP:
								if mCall.HangupAt() == 0 {
									mCall.Hangup("", false) //TODO
									mCall.WaitForHangup()
								}
								break top
							}

						case mState := <-mCall.State():

							switch mState {
							case call_manager.CALL_STATE_BRIDGE:
								attempt.Log("bridged")
								team.Bridged(attempt, agent)
							case call_manager.CALL_STATE_HANGUP:
								attempt.Log(fmt.Sprintf("call hangup %s", mCall.Id()))
								if agentCall.HangupAt() == 0 {
									if mCall.BridgeAt() > 0 {
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
					}
				}
			}
		case <-mCall.HangupChan():
			calling = false
		}
	}

	if agentCall == nil {
		team.Cancel(attempt, agent, uint(queue.MaxAttempts), uint64(queue.WaitBetweenRetries))
	} else {
		if agentCall.AnswerSeconds() > 0 { //FIXME Accept or Bridge ?
			wlog.Debug(fmt.Sprintf("attempt[%d] reporting...", attempt.Id()))
			team.Reporting(queue, attempt, agent, agentCall.ReportingAt() > 0)
		} else {
			//FIXME cancel if progressive cnt > 1
			team.Missed(attempt, queue.WaitBetweenRetries, agent)
		}
	}

}
