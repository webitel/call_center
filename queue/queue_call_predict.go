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
	Recordings    bool `json:"recordings"`
	RecordStereo  bool `json:"record_stereo"`
	RecordBridged bool `json:"record_bridged"`

	MaxWaitTime            uint16 `json:"max_wait_time"`
	WaitBetweenRetries     uint64 `json:"wait_between_retries"`
	WaitBetweenRetriesDesc bool   `json:"wait_between_retries_desc"`
	MaxAttempts            uint   `json:"max_attempts"`
	OriginateTimeout       uint16 `json:"originate_timeout"`
	RetryAbandoned         bool   `json:"retry_abandoned"`
	AllowGreetingAgent     bool   `json:"allow_greeting_agent"`
	Amd                    *model.QueueAmdSettings
}

func PredictCallQueueSettingsFromBytes(data []byte) PredictCallQueueSettings {
	var settings PredictCallQueueSettings
	json.Unmarshal(data, &settings)
	return settings
}

type PredictCallQueue struct {
	PredictCallQueueSettings
	CallingQueue
	Amd *model.QueueAmdSettings
}

func NewPredictCallQueue(callQueue CallingQueue, settings PredictCallQueueSettings) QueueObject {

	if settings.MaxWaitTime == 0 {
		settings.MaxWaitTime = 10
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

	team, err := queue.GetTeam(attempt)
	if err != nil {
		return err
	}

	go queue.runPark(attempt, team)

	return nil
}

func (queue *PredictCallQueue) runPark(attempt *Attempt, team *agentTeam) {

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
				"park_timeout":           fmt.Sprintf("%d", queue.MaxWaitTime),

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

	if queue.Recordings {
		queue.SetRecordings(mCall, queue.RecordBridged, queue.RecordStereo)
	}

	if !queue.SetAmdCall(callRequest, queue.Amd, "park") {
		callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
			AppName: "park",
		})
	}

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

				queue.runOfferingAgents(attempt, team, mCall)
				return
			}
		case <-mCall.HangupChan():
			calling = false
		}
	}

	queue.queueManager.SetAttemptAbandonedWithParams(attempt, queue.MaxAttempts, queue.WaitBetweenRetries, nil)
	queue.queueManager.LeavingMember(attempt)

}

func (queue *PredictCallQueue) runOfferingAgents(attempt *Attempt, team *agentTeam, mCall call_manager.Call) {
	attempt.Log("answer & wait agent")
	if err := queue.queueManager.AnswerPredictAndFindAgent(attempt.Id()); err != nil {
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
	timeout := time.NewTimer(time.Second * time.Duration(queue.MaxWaitTime))

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
			attempt.Log(fmt.Sprintf("distribute agent %s [%d]", agent.Name(), agent.Id()))

			attempts++
			if mCall.HangupCause() != "" {
				attempt.Log(fmt.Sprintf("agent %s LOSE_RACE", agent.Name()))
				calling = false
				break
			}

			cr := queue.AgentCallRequest(agent, team, attempt, []*model.CallRequestApplication{
				{
					AppName: "park",
					Args:    "",
				},
			})

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
						printfIfErr(agentCall.Bridge(mCall))

						if queue.AllowGreetingAgent {
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
			}

			calling = mCall.HangupAt() == 0 && mCall.BridgeAt() == 0
		}
	}

	if agentCall != nil && agentCall.HangupAt() == 0 {
		wlog.Warn(fmt.Sprintf("agent call %s no hangup", agentCall.Id()))
	}

	if agentCall != nil && agentCall.BridgeAt() > 0 {
		team.Reporting(queue, attempt, agent, agentCall.ReportingAt() > 0)
	} else if queue.RetryAbandoned {
		queue.queueManager.SetAttemptAbandonedWithParams(attempt, queue.MaxAttempts, queue.WaitBetweenRetries, nil)
	} else {
		queue.queueManager.Abandoned(attempt)
	}

	go func() {
		attempt.Emit(AttemptHookLeaving)
		attempt.Off("*")
	}()
}
