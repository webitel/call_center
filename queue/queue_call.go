package queue

import (
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
)

const (
	amdMachineApplication = "hangup::NORMAL_UNSPECIFIED"
)

type CallingQueueObject interface {
}

type CallingQueue struct {
	BaseQueue
	params model.QueueDialingSettings
}

func (queue *CallingQueue) CallContextName() string {
	return "call_center"
}

func (queue *CallingQueue) FlowEndpoints() []string {
	return []string{"null"}
}

func (queue *CallingQueue) GetRecordingsApplication(call call_manager.Call) *model.CallRequestApplication {
	return &model.CallRequestApplication{
		AppName: "record_session",
		Args: fmt.Sprintf("http_cache://http://$${cdr_url}/sys/recordings?domain=%d&id=%s&name=%s_%s&.%s", queue.DomainId(),
			call.Id(), call.Id(), "recordFile", "mp3"),
	}
}

func (queue *CallingQueue) SetAmdCall(callRequest *model.CallRequest, amd *model.QueueAmdSettings, onHuman string) bool {
	if amd == nil || !amd.Enabled {
		return false
	}

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

	if amd.PlaybackFileUri != "" {
		if amd.PlaybackFileSilenceTime > 0 {
			callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
				AppName: model.CALL_SLEEP_APPLICATION,
				Args:    fmt.Sprintf("%d", amd.PlaybackFileSilenceTime),
			})
		}

		callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
			AppName: model.CALL_PLAYBACK_APPLICATION,
			Args:    amd.PlaybackFileUri,
		})

		if amd.TotalAnalysisTime-amd.PlaybackFileSilenceTime > 0 {
			callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
				AppName: model.CALL_SLEEP_APPLICATION,
				Args:    fmt.Sprintf("%d", amd.TotalAnalysisTime-amd.PlaybackFileSilenceTime+100), // TODO 100 ?
			})
		}
	} else {
		callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
			AppName: model.CALL_SLEEP_APPLICATION,
			Args:    fmt.Sprintf("%d", amd.TotalAnalysisTime+100),
		})
	}

	return true
}

func (queue *CallingQueue) NewCall(callRequest *model.CallRequest) call_manager.Call {
	return queue.queueManager.callManager.NewCall(callRequest)
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

func (queue *CallingQueue) NewCallUseResource(callRequest *model.CallRequest, resource ResourceObject) call_manager.Call {
	resource.Take() // rps

	callRequest.Variables = model.UnionStringMaps(
		callRequest.Variables,
		resource.Variables(),
		resource.Gateway().Variables(),
	)

	call := queue.queueManager.callManager.NewCall(callRequest)
	if call.Err() != nil {
		queue.queueManager.SetResourceError(resource, fmt.Sprintf("%d", call.HangupCauseCode()))
	} else {
		queue.queueManager.SetResourceSuccessful(resource)
	}
	return call
}

func (queue *CallingQueue) GetCallInfoFromAttempt(attempt *Attempt) *AttemptInfoCall {
	if attempt.Info == nil {
		attempt.Info = &AttemptInfoCall{}
	}
	return attempt.Info.(*AttemptInfoCall)
}

func (queue *BaseQueue) AgentMissedCall(agent agent_manager.AgentObject, attempt *Attempt, call call_manager.Call) {
	queue.queueManager.store.Agent().MissedAttempt(agent.Id(), attempt.Id(), call.HangupCause())
}
