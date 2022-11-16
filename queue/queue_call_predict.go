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

type PredictCallQueueSettings struct {
	Recordings bool `json:"recordings"`
	RecordMono bool `json:"record_mono"`
	RecordAll  bool `json:"record_all"`

	MaxWaitTime            uint16                  `json:"max_wait_time"`
	WaitBetweenRetries     uint64                  `json:"wait_between_retries"`
	WaitBetweenRetriesDesc bool                    `json:"wait_between_retries_desc"`
	MaxAttempts            uint                    `json:"max_attempts"`
	PerNumbers             bool                    `json:"per_numbers"`
	OriginateTimeout       uint16                  `json:"originate_timeout"`
	RetryAbandoned         bool                    `json:"retry_abandoned"`
	AllowGreetingAgent     bool                    `json:"allow_greeting_agent"`
	Amd                    *model.QueueAmdSettings `json:"amd"`

	MinAttempts      uint `json:"min_attempts"`
	MaxAbandonedRate uint `json:"max_abandoned_rate"`
	MaxAgentLine     uint `json:"max_agent_line"`
	PlaybackSilence  uint `json:"playback_silence"`
}

func PredictCallQueueSettingsFromBytes(data []byte) PredictCallQueueSettings {
	var settings PredictCallQueueSettings
	json.Unmarshal(data, &settings)
	return settings
}

type PredictCallQueue struct {
	PredictCallQueueSettings
	CallingQueue
}

func NewPredictCallQueue(callQueue CallingQueue, settings PredictCallQueueSettings) QueueObject {

	if settings.MaxWaitTime == 0 {
		settings.MaxWaitTime = 30
	}

	return &PredictCallQueue{
		CallingQueue:             callQueue,
		PredictCallQueueSettings: settings,
	}
}

func (queue *PredictCallQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	if attempt.resource == nil {
		return NewErrorResourceRequired(queue, attempt)
	}

	attempt.waitBetween = queue.WaitBetweenRetries
	attempt.maxAttempts = queue.MaxAttempts
	attempt.perNumbers = queue.PerNumbers

	go queue.runPark(attempt)

	return nil
}

func (queue *PredictCallQueue) runPark(attempt *Attempt) {

	if !queue.queueManager.DoDistributeSchema(&queue.BaseQueue, attempt) {
		queue.queueManager.LeavingMember(attempt)
		return
	}

	dst := attempt.resource.Gateway().Endpoint(attempt.Destination())
	var callerIdNumber = attempt.Display()

	attempt.Log("JOINED")

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
				"park_timeout": fmt.Sprintf("%d", queue.MaxWaitTime),

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

	attempt.resource.Take() // rps

	callRequest.Variables = model.UnionStringMaps(
		callRequest.Variables,
		attempt.resource.Variables(),
		attempt.resource.Gateway().Variables(),
	)

	attempt.Log("make member call")

	mCall, err := queue.queueManager.callManager.NewCall(callRequest)
	//mCall, err := queue.NewCallUseResource(callRequest, attempt.resource)
	if err != nil {
		attempt.Log(err.Error())
		// TODO
		queue.queueManager.SetAttemptAbandonedWithParams(attempt, queue.MaxAttempts, queue.WaitBetweenRetries, nil)
		queue.queueManager.LeavingMember(attempt)
		return
	}

	attempt.Log("make call")

	if queue.Recordings {
		queue.SetRecordings(mCall, queue.RecordAll, queue.RecordMono)
	}

	if !queue.SetAmdCall(callRequest, queue.Amd, "park") {
		callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
			AppName: "park",
		})
	}
	attempt.memberChannel = mCall
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

				if queue.HasRingtone() {
					mCall.BroadcastPlaybackSilenceBeforeFile(queue.domainId, queue.PlaybackSilence, queue.Ringtone(), "both")
				}

				queue.runOfferingAgents(attempt, mCall)
				return
			}
		case <-mCall.HangupChan():
			calling = false
		}
	}
	queue.CallCheckResourceError(attempt.resource, mCall)

	if !queue.queueManager.SendAfterDistributeSchema(attempt) {
		queue.queueManager.SetAttemptAbandonedWithParams(attempt, queue.MaxAttempts, queue.WaitBetweenRetries, nil)
		queue.queueManager.LeavingMember(attempt)
	}

}

func (queue *PredictCallQueue) runOfferingAgents(attempt *Attempt, mCall call_manager.Call) {
	var team *agentTeam
	var agent agent_manager.AgentObject
	var agentCall call_manager.Call

	var err *model.AppError

	var predictAgentId = 0
	if attempt.agent != nil {
		predictAgentId = attempt.agent.Id()
	}

	attempt.Log("answer & wait agent")
	if err = queue.queueManager.AnswerPredictAndFindAgent(attempt.Id()); err != nil {
		wlog.Error(err.Error())
		time.Sleep(time.Second * 3)
		return
	}
	attempt.SetState(model.MemberStateWaitAgent)

	attempts := 0

	var calling = mCall.HangupAt() == 0

	ags := attempt.On(AttemptHookDistributeAgent)

	//TODO
	timeout := time.NewTimer(time.Second * time.Duration(queue.MaxWaitTime))

	for calling {
		select {
		case <-timeout.C:
			calling = false
			mCall.Hangup(model.CALL_HANGUP_ORIGINATOR_CANCEL, false, nil) //TODO
			mCall.WaitForHangup()
		case <-attempt.Context.Done():
			calling = false
			mCall.Hangup(model.CALL_HANGUP_ORIGINATOR_CANCEL, false, nil) //TODO
			mCall.WaitForHangup()
		case c := <-mCall.State():
			if c == call_manager.CALL_STATE_HANGUP {
				calling = false
				break
			} else {
				wlog.Debug(fmt.Sprintf("[%d] change call state to %s", attempt.Id(), c))
			}

		case <-ags:
			agent = attempt.Agent()
			team, err = queue.GetTeam(attempt)
			if err != nil {
				wlog.Error(err.Error())
				time.Sleep(time.Second * 3)
				return
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

			agentCall = mCall.NewCall(cr)
			attempt.agentChannel = agentCall

			team.Distribute(queue, agent, NewDistributeEvent(attempt, agent.UserId(), queue, agent, queue.Processing(), mCall, agentCall))
			agentCall.Invite()

			wlog.Debug(fmt.Sprintf("call [%s] && agent [%s]", mCall.Id(), agentCall.Id()))

		top:
			for agentCall.HangupCause() == "" && (mCall.HangupCause() == "") {
				select {
				case state := <-agentCall.State():
					attempt.Log(fmt.Sprintf("agent call state %d", state))
					switch state {
					case call_manager.CALL_STATE_RINGING:
						team.Offering(attempt, agent, agentCall, mCall)

					case call_manager.CALL_STATE_ACCEPT:
						attempt.Emit(AttemptHookBridgedAgent, agentCall.Id())
						time.Sleep(time.Millisecond * 250)
						if err = agentCall.Bridge(mCall); err != nil {
							if agentCall.HangupAt() == 0 {
								agentCall.Hangup(model.CALL_HANGUP_LOSE_RACE, false, nil)
							}
							printfIfErr(err)
						}

						if queue.AllowGreetingAgent {
							mCall.BroadcastPlaybackFile(agent.DomainId(), agent.GreetingMedia(), "both")
						} else if queue.AutoAnswer() {
							agentCall.BroadcastTone("aleg")
						}

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
									goto top
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

	if mCall.HangupCause() == "" && (agentCall == nil || !agentCall.Transferred()) {
		//TODO
		select {
		case <-mCall.HangupChan():
			break
		case <-time.After(time.Second):
			break
		}
	}

	if agentCall != nil && agentCall.BridgeAt() > 0 {
		team.Reporting(queue, attempt, agent, agentCall.ReportingAt() > 0, agentCall.Transferred())
	} else {
		queue.queueManager.LosePredictAgent(predictAgentId)

		if !queue.queueManager.SendAfterDistributeSchema(attempt) {
			if queue.RetryAbandoned {
				queue.queueManager.SetAttemptAbandonedWithParams(attempt, queue.MaxAttempts, queue.WaitBetweenRetries, nil)
				queue.queueManager.LeavingMember(attempt)
			} else {
				queue.queueManager.Abandoned(attempt)
			}
		}
	}

	go func() {
		attempt.Off("*")
	}()
}
