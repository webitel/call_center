package queue

import (
	"fmt"
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
	HoldMusic *model.RingtoneFile
	granteeId *int
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

	pbf := queue.AmdPlaybackUri()

	if amd.Ai {
		if pbf != nil {
			callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
				AppName: "set",
				Args:    "execute_on_answer=playback " + *pbf,
			})
		}

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

		if pbf != nil {
			callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
				AppName: "playback",
				Args:    *pbf,
			})
		}

		callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
			AppName: model.CALL_SLEEP_APPLICATION,
			Args:    fmt.Sprintf("%d", amd.TotalAnalysisTime+100),
		})
	}

	return true
}

func (queue *CallingQueue) NewCall(callRequest *model.CallRequest) (call_manager.Call, *model.AppError) {
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
