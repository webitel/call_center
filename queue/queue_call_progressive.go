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
	Recordings bool `json:"recordings"`
	RecordMono bool `json:"record_mono"`
	RecordAll  bool `json:"record_all"`

	WaitBetweenRetries     uint64                  `json:"wait_between_retries"`
	WaitBetweenRetriesDesc bool                    `json:"wait_between_retries_desc"`
	MaxAttempts            uint                    `json:"max_attempts"`
	PerNumbers             bool                    `json:"per_numbers"`
	OriginateTimeout       uint16                  `json:"originate_timeout"`
	AllowGreetingAgent     bool                    `json:"allow_greeting_agent"`
	Amd                    *model.QueueAmdSettings `json:"amd"`
	AutoAnswerTone         *string                 `json:"auto_answer_tone"`
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

	attempt.waitBetween = queue.WaitBetweenRetries
	attempt.maxAttempts = queue.MaxAttempts
	attempt.perNumbers = queue.PerNumbers

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
	var callerIdNumber = attempt.Display()

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
				"ignore_early_media":     "true", // ???
				//"absolute_codec_string":  "pcmu,pcma",

				"sip_h_X-Webitel-Display-Direction": "outbound",
				"sip_h_X-Webitel-Origin":            "request",
				"wbt_destination":                   attempt.Destination(),
				"wbt_from_id":                       fmt.Sprintf("%v", attempt.resource.Gateway().Id), //FIXME gateway id ?
				"wbt_from_number":                   callerIdNumber,
				//"wbt_from_name":                     attempt.resource.Gateway().Name,
				"wbt_from_type": "gateway",

				"wbt_to_id":     fmt.Sprintf("%d", *attempt.MemberId()),
				"wbt_to_name":   attempt.Name(),
				"wbt_to_type":   "member",
				"wbt_to_number": attempt.Destination(),

				"effective_caller_id_number": callerIdNumber,
				//"effective_caller_id_name":   attempt.resource.Name(),

				"effective_callee_id_name":   attempt.Name(),
				"effective_callee_id_number": attempt.Destination(),

				//"origination_caller_id_name":   attempt.resource.Name(),
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

	mCall, err := queue.NewCallUseResource(callRequest, attempt.resource)
	if err != nil {
		attempt.Log(err.Error())
		// TODO
		queue.queueManager.SetAttemptAbandonedWithParams(attempt, queue.MaxAttempts, queue.WaitBetweenRetries, nil)
		queue.queueManager.LeavingMember(attempt)
		return
	}

	var agentCall call_manager.Call

	if queue.Recordings {
		queue.SetRecordings(mCall, queue.RecordAll, queue.RecordMono)
	}

	if attempt.communication.Dtmf != nil {
		callRequest.SetAutoDtmf(*attempt.communication.Dtmf)
	}

	if !queue.SetAmdCall(callRequest, queue.Amd, "park") {
		callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
			AppName: "park",
		})
	}

	//FIXME update member call id
	team.Distribute(queue, agent, NewDistributeEvent(attempt, agent.UserId(), queue, agent, queue.Processing(), nil, mCall))
	attempt.memberChannel = mCall
	mCall.Invite()

	var calling = true

	for calling {
		select {
		case <-attempt.Cancel():
			mCall.Hangup(model.CALL_HANGUP_ORIGINATOR_CANCEL, false, nil)
		case state := <-mCall.State():
			switch state {
			case call_manager.CALL_STATE_ACCEPT, call_manager.CALL_STATE_DETECT_AMD:
				// FIXME
				if (state == call_manager.CALL_STATE_ACCEPT && queue.Amd != nil && queue.Amd.Enabled) || (state == call_manager.CALL_STATE_DETECT_AMD && !IsHuman(mCall, queue.Amd)) {
					continue
				}

				if cnt, err := queue.queueManager.store.Agent().ConfirmAttempt(agent.Id(), attempt.Id()); err != nil || len(cnt) == 0 {
					// todo fixme
					if err != nil {
						attempt.Log(err.Error())
					}
					printfIfErr(mCall.Hangup(model.CALL_HANGUP_ORIGINATOR_CANCEL, false, nil))
				} else if len(cnt) > 0 {

					go queue.HangupManyCall(mCall.Id(), model.CALL_HANGUP_ORIGINATOR_CANCEL, cnt...)

					if queue.HasRingtone() {
						mCall.ParkPlaybackFile(queue.domainId, queue.Ringtone(), "aleg")
					}

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
					cr.CheckParentId = mCall.Id()

					agentCall = mCall.NewCall(cr)
					attempt.agentChannel = agentCall

					//todo
					if mCall.HangupCause() != "" {
						calling = false
						continue
					}

					printfIfErr(agentCall.Invite())
					wlog.Debug(fmt.Sprintf("call [%s] && agent [%s]", mCall.Id(), agentCall.Id()))

				top:
					for agentCall.HangupCause() == "" && mCall.HangupCause() == "" && agentCall.TransferTo() == nil {
						select {
						case state := <-agentCall.State():
							attempt.Log(fmt.Sprintf("agent call state %d", state))
							switch state {
							case call_manager.CALL_STATE_RINGING:
								team.Offering(attempt, agent, agentCall, mCall)

							case call_manager.CALL_STATE_ACCEPT:
								time.Sleep(time.Millisecond * 250)
								if err = agentCall.Bridge(mCall); err != nil {
									if agentCall.HangupAt() == 0 {
										agentCall.Hangup(model.CALL_HANGUP_LOSE_RACE, false, nil)
									}
									calling = false
									printfIfErr(err)
									continue
								}

								//fixme refactor
								if queue.AllowGreetingAgent && agent.GreetingMedia() != nil {
									mCall.BroadcastPlaybackFile(agent.DomainId(), agent.GreetingMedia(), "both")
								} else if queue.AutoAnswer() {
									agentCall.BroadcastTone(queue.AutoAnswerTone, "aleg")
								}

								//team.Answered(attempt, agent)
							case call_manager.CALL_STATE_HANGUP:

								if agentCall.TransferTo() != nil && agentCall.TransferToAgentId() != nil && agentCall.TransferFromAttemptId() != nil {
									attempt.Log("receive transfer")
									if nc, err := queue.GetTransferredCall(*agentCall.TransferTo()); err != nil {
										wlog.Error(err.Error())
									} else {
										if nc.HangupAt() == 0 {
											if newA, err := queue.queueManager.TransferFrom(team, attempt, *agentCall.TransferFromAttemptId(), *agentCall.TransferToAgentId(), *agentCall.TransferTo(), nc); err == nil {
												agent = newA
												attempt.Log(fmt.Sprintf("transfer call from [%s] to [%s] AGENT_ID = %s {%d, %d}", agentCall.Id(), nc.Id(), newA.Name(), attempt.Id(), *agentCall.TransferFromAttemptId()))
												//transferred = true
											} else {
												wlog.Error(err.Error())
											}

											agentCall = nc
											attempt.agentChannel = agentCall
											break top
										}
									}
								}

								// check transfer to internal number
								if mCall.HangupAt() == 0 && agentCall.BillSeconds() == 0 && agentCall.TransferTo() == nil {
									mCall.Hangup(model.CALL_HANGUP_LOSE_RACE, false, nil)
									//mCall.WaitForHangup()
								}
								// if internal transfer
								calling = false
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
										agentCall.Hangup(model.CALL_HANGUP_NORMAL_CLEARING, false, nil)
									} else {
										agentCall.Hangup(model.CALL_HANGUP_ORIGINATOR_CANCEL, false, nil)
									}
									agentCall.WaitForHangup()
								}

								attempt.Log(fmt.Sprintf("[%s] call %s receive hangup", agentCall.NodeName(), agentCall.Id()))
								break top
							}
						}
					}
				} else {
					attempt.Log(fmt.Sprintf("error logic"))
				}
			}
		case <-mCall.HangupChan():
			calling = false
		}
	}

	queue.CallCheckResourceError(attempt.resource, mCall)

	if agentCall == nil {
		team.Cancel(attempt, agent)
		queue.queueManager.LeavingMember(attempt)
	} else {
		if agentCall.BridgeAt() > 0 { //FIXME Accept or Bridge ?
			wlog.Debug(fmt.Sprintf("attempt[%d] reporting...", attempt.Id()))
			team.Reporting(queue, attempt, agent, agentCall.ReportingAt() > 0, agentCall.Transferred())
		} else {
			if agentCall.HangupAt() == 0 && agentCall.TransferTo() == nil && mCall.HangupAt() > 0 {
				time.Sleep(time.Millisecond * 200) // todo WTEL-4057
				agentCall.Hangup(model.CALL_HANGUP_ORIGINATOR_CANCEL, false, nil)
			}
			//FIXME cancel if progressive cnt > 1
			team.Missed(attempt, agent)
			queue.queueManager.LeavingMember(attempt)
		}
	}

}
