package queue

import (
	"fmt"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
)

type CallingQueueObject interface {
}

type CallingQueue struct {
	BaseQueue
	params model.QueueDialingSettings
}

func (queue *CallingQueue) RecordCallEnabled() bool {
	return queue.params.Recordings
}

func (queue *CallingQueue) SetRecordCall(callRequest *model.CallRequest, template string) {
	callRequest.Variables[model.CALL_RECORD_MIN_SEC_VARIABLE] = "2"
	callRequest.Variables[model.CALL_RECORD_STEREO_VARIABLE] = "false"
	callRequest.Variables[model.CALL_RECORD_BRIDGE_REQ_VARIABLE] = "false"
	callRequest.Variables[model.CALL_RECORD_FLLOW_TRANSFER_VARIABLE] = "true"

	callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
		AppName: model.CALL_RECORD_SESSION_APPLICATION_NAME,
		Args:    template,
	})
}

func (queue *CallingQueue) SetAmdCall(callRequest *model.CallRequest, amd *model.QueueAmdSettings, onHuman, onMachine, onNotSure string) {
	callRequest.Variables[model.CALL_AMD_HUMAN_VARIABLE] = onHuman
	callRequest.Variables[model.CALL_AMD_MACHINE_VARIABLE] = onMachine
	callRequest.Variables[model.CALL_AMD_NOT_SURE_VARIABLE] = onNotSure

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
}

func (queue *CallingQueue) NewCallUseResource(callRequest *model.CallRequest, routingId int, resource ResourceObject) call_manager.Call {
	resource.Take() // rps

	DUMP(callRequest)

	call := queue.queueManager.callManager.NewCall(callRequest)
	if call.Err() != nil {
		queue.queueManager.SetResourceError(resource, routingId, call.HangupCause())
	} else {
		queue.queueManager.SetResourceSuccessful(resource)
	}
	return call
}

func (queue *CallingQueue) CallError(attempt *Attempt, callErr *model.AppError, cause string) *model.AppError {
	attempt.Log("error: " + callErr.Error())
	info := queue.GetCallInfoFromAttempt(attempt)
	info.Error = model.NewString(callErr.Error())
	return queue.StopAttemptWithCallDuration(attempt, cause, 0)
}

func (queue *CallingQueue) StopAttemptWithCallDuration(attempt *Attempt, cause string, talkDuration int) *model.AppError {
	var err *model.AppError
	var stopped bool

	if queue.params.InCauseSuccess(cause) && queue.params.MinCallDuration <= talkDuration {
		attempt.Log("call is success")
		err = queue.queueManager.SetAttemptSuccess(attempt, cause)
	} else if queue.params.InCauseError(cause) {
		attempt.Log("call is error")
		stopped, err = queue.queueManager.SetAttemptError(attempt, cause)
	} else if queue.params.InCauseMinusAttempt(cause) {
		attempt.Log("call is minus attempt")
		stopped, err = queue.queueManager.SetAttemptMinus(attempt, cause)
	} else {
		attempt.Log("call is attempt")
		stopped, err = queue.queueManager.SetAttemptStop(attempt, cause)
	}

	queue.queueManager.notifyStopAttempt(attempt, stopped)

	if err != nil {
		panic(err.Error())
	}

	return err
}

func (queue *CallingQueue) GetCallInfoFromAttempt(attempt *Attempt) *AttemptInfoCall {
	if attempt.Info == nil {
		attempt.Info = &AttemptInfoCall{}
	}
	return attempt.Info.(*AttemptInfoCall)
}
