package queue

import (
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
	"time"
)

const (
	amdMachineApplication = "hangup::NORMAL_UNSPECIFIED"
)

type CallingQueueObject interface {
}

type CallingQueue struct {
	BaseQueue
	HoldMusic   *model.RingtoneFile
	granteeId   *int
	bridgeSleep time.Duration
}

type Caller struct {
	Number string
	Name   string
}

func (queue *CallingQueue) SetRecordings(call call_manager.Call, all, mono bool) {
	call.SetRecordings(queue.domainId, all, mono)
}

func (queue *CallingQueue) HasRingtone() bool {
	return queue.ringtoneUri != nil
}

func (queue *CallingQueue) Ringtone() *model.RingtoneFile {
	return queue.ringtone
}

func (queue *CallingQueue) SetHoldMusic(callRequest *model.CallRequest) {
	if queue.HoldMusic != nil {
		hm := queue.CallManager().RingtoneUri(queue.domainId, queue.HoldMusic.Id, queue.HoldMusic.Type)
		callRequest.Variables["hold_music"] = hm
		callRequest.Variables["transfer_ringback"] = hm
	}
}

func (queue *CallingQueue) SetAmdCall(callRequest *model.CallRequest, amd *model.QueueAmdSettings, onHuman string) bool {
	if amd == nil || !amd.Enabled {
		return false
	}

	if amd.Ai {
		callRequest.Variables["ignore_early_media"] = "false"
		callRequest.Variables["amd_on_positive"] = onHuman
		callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
			AppName: "wbt_amd",    // todo if error skip and call
			Args:    amd.AiTags(), // positive labels
		})

		callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
			AppName: "park",
			Args:    "",
		})

	} else {
		if !amd.AllowNotSure {
			callRequest.Variables[model.CALL_AMD_NOT_SURE_VARIABLE] = amdMachineApplication
		} else {
			callRequest.Variables[model.CALL_AMD_NOT_SURE_VARIABLE] = onHuman
		}
		callRequest.Variables[model.CALL_AMD_MACHINE_VARIABLE] = amdMachineApplication
		callRequest.Variables[model.CALL_AMD_HUMAN_VARIABLE] = onHuman

		callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
			AppName: model.CALL_AMD_APPLICATION_NAME,
			Args:    amd.ToArgs(),
		})

		if queue.amdPlaybackFileUri != nil {
			// TODO BroadcastPlaybackFile - blocking call
			callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
				AppName: "playback",
				Args:    *queue.amdPlaybackFileUri,
			})
		}

		callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
			AppName: model.CALL_SLEEP_APPLICATION,
			Args:    fmt.Sprintf("%d", amd.TotalAnalysisTime+100),
		})
	}

	return true
}

func (queue *CallingQueue) hasProcessAmd(call call_manager.Call, state call_manager.CallState, amd *model.QueueAmdSettings) bool {
	if (state == call_manager.CALL_STATE_ACCEPT && !call.HasAmdError() && amd != nil && amd.Enabled) ||
		(state == call_manager.CALL_STATE_DETECT_AMD && !IsHuman(call, amd)) {

		// TODO
		if amd.Ai {
			if queue.amdPlaybackFile != nil {
				_ = call.BroadcastPlaybackFile(queue.DomainId(), queue.amdPlaybackFile, "aleg")
			}
		}
		return true
	}

	return false
}

func (queue *CallingQueue) NewCall(callRequest *model.CallRequest) (call_manager.Call, *model.AppError) {
	return queue.queueManager.callManager.NewCall(callRequest)
}

func (queue *CallingQueue) AgentCallRequest(agent agent_manager.AgentObject, at *agentTeam, attempt *Attempt, caller Caller, apps []*model.CallRequestApplication) *model.CallRequest {
	cr := &model.CallRequest{
		Endpoints:   agent.GetCallEndpoints(),
		Strategy:    model.CALL_STRATEGY_DEFAULT,
		Destination: attempt.Destination(),
		Variables: model.UnionStringMaps(
			queue.Variables(),
			attempt.ExportVariables(),
			agent.Variables(),
			map[string]string{
				//"ignore_early_media": "true",
				//"absolute_codec_string": "opus,pcmu,pcma",
				//"sip_h_X-Webitel-Display-Direction": "inbound",
				//"bypass_media_resume_on_hold": "true",
				"hangup_after_bridge":       "true",
				"ignore_display_updates":    "true",
				"cc_reporting":              fmt.Sprintf("%v", queue.Processing()),
				model.CallVariableDomainId:  fmt.Sprintf("%v", queue.DomainId()),
				model.CallVariableUserId:    fmt.Sprintf("%v", agent.UserId()),
				"bridge_export_vars":        "cc_agent_id",
				"sip_h_X-Webitel-Direction": "internal",
				"wbt_destination":           attempt.Destination(),
				"wbt_to_id":                 fmt.Sprintf("%v", agent.Id()),
				"wbt_to_number":             agent.CallNumber(),
				"wbt_to_name":               agent.Name(),
				"wbt_to_type":               "user", //todo agent ?

				"wbt_from_name":   attempt.Name(),
				"wbt_from_type":   "member",
				"wbt_from_number": attempt.Destination(),

				//"effective_caller_id_name":   attempt.Name(),
				//"effective_caller_id_number": attempt.Destination(),
				//
				//"origination_callee_id_name":   attempt.Name(),
				//"origination_callee_id_number": attempt.Destination(),
				"origination_caller_id_name":   caller.Name,
				"origination_caller_id_number": caller.Number,

				model.QUEUE_AGENT_ID_FIELD:   fmt.Sprintf("%d", agent.Id()),
				model.QUEUE_TEAM_ID_FIELD:    fmt.Sprintf("%d", at.Id()),
				model.QUEUE_NAME_FIELD:       queue.Name(),
				model.QUEUE_TYPE_NAME_FIELD:  queue.TypeName(),
				model.QUEUE_ATTEMPT_ID_FIELD: fmt.Sprintf("%d", attempt.Id()),
			},
		),
		Timeout: at.CallTimeout(),
		//CallerName:   agent.Name(),
		//CallerNumber: agent.CallNumber(),
	}

	if agent.HasPush() {
		cr.SetPush()
	}

	queue.SetHoldMusic(cr)

	if queue.id > 0 {
		cr.Variables[model.QUEUE_ID_FIELD] = fmt.Sprintf("%d", queue.Id())
	}

	if attempt.MemberId() != nil {
		cr.Variables["wbt_from_id"] = fmt.Sprintf("%d", *attempt.MemberId())
		cr.Variables[model.QUEUE_MEMBER_ID_FIELD] = cr.Variables["wbt_from_id"]
	}

	if agent.GreetingMedia() != nil {
		cr.Applications = append([]*model.CallRequestApplication{
			{
				AppName: "playback",
				Args:    model.RingtoneUri(agent.DomainId(), agent.GreetingMedia().Id, agent.GreetingMedia().Type),
			},
		}, apps...)
	} else {
		cr.Applications = apps
	}

	return cr
}

func (queue *CallingQueue) HangupManyCall(skipId, cause string, ids ...string) {
	if len(ids) == 1 {

		return
	}

	res := make([]string, 0, len(ids)-1)
	for _, v := range ids {
		if v != skipId {
			res = append(res, v)
		}
	}

	if len(res) > 0 {
		queue.queueManager.callManager.HangupManyCall(cause, res...)
	}
}

func (queue *CallingQueue) NewCallUseResource(callRequest *model.CallRequest, resource ResourceObject) (call_manager.Call, *model.AppError) {
	resource.Take() // rps

	callRequest.Variables = model.UnionStringMaps(
		callRequest.Variables,
		resource.Variables(),
		resource.Gateway().Variables(),
	)

	return queue.queueManager.callManager.NewCall(callRequest)
}

func (queue *CallingQueue) CallCheckResourceError(resource ResourceObject, call call_manager.Call) {
	if call.Err() != nil {
		queue.queueManager.SetResourceError(resource, fmt.Sprintf("%d", call.HangupCauseCode()))
	} else {
		queue.queueManager.SetResourceSuccessful(resource)
	}
}

func (queue *CallingQueue) GetTransferredCall(id string) (call_manager.Call, *model.AppError) {
	var call call_manager.Call
	var err *model.AppError
	var callInfo *model.Call
	var ok bool

	if call, ok = queue.queueManager.callManager.GetCall(id); ok && call.HangupAt() == 0 {
		return call, nil
	}

	callInfo, err = queue.queueManager.store.Call().Get(id)
	if err != nil {
		return nil, err
	}

	call, err = queue.queueManager.callManager.ConnectCall(callInfo, "")
	if err != nil {
		return nil, err
	}
	return call, nil
}

func (queue *CallingQueue) GranteeId() *int {
	return queue.granteeId
}

func (queue *CallingQueue) MissedAgentAttempt(attemptId int64, agentId int, call call_manager.Call) *model.AppError {
	missed := &model.MissedAgentAttempt{
		AttemptId: attemptId,
		AgentId:   agentId,
		Cause:     call.HangupCause(),
		MissedAt:  call.HangupAt(),
	}

	return queue.queueManager.store.Agent().CreateMissed(missed)
}

func IsHuman(call call_manager.Call, amd *model.QueueAmdSettings) bool {
	if amd == nil || !amd.Enabled {
		return true
	}

	if amd.Ai {
		aiAmd := call.AiResult()
		answered := call.Answered()
		if aiAmd.Error != "" || aiAmd.Result == "undefined" {
			return answered // TODO ? DEV-3338
		}
		for _, v := range amd.PositiveTags {
			if v == aiAmd.Result {
				if !answered && call.HangupAt() == 0 { // TODO ? DEV-3338
					call.Hangup(model.CALL_HANGUP_NORMAL_UNSPECIFIED, false, nil)
					return false
				}
				return true
			}
		}
		return false
	}

	return call.IsHuman()
}
