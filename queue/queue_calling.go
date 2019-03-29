package queue

import (
	"fmt"
	"github.com/webitel/call_center/model"
)

type CallingQueueObject interface {
	SetHangupCall(attempt *Attempt, event Event)
}

type CallingQueue struct {
	BaseQueue
	params model.QueueDialingSettings
}

func (queue *CallingQueue) RecordCall() bool {
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

func (queue *CallingQueue) NewCallToMember(callRequest *model.CallRequest, routingId int, resource ResourceObject) (string, string, *model.AppError) {
	resource.Take() // rps
	id, cause, err := queue.queueManager.app.NewCall(callRequest)
	if err != nil {
		queue.queueManager.SetResourceError(resource, routingId, cause)
		return "", cause, err
	}

	queue.queueManager.SetResourceSuccessful(resource)
	return id, "", nil
}

func (queue *CallingQueue) CallError(attempt *Attempt, callErr *model.AppError, cause string) *model.AppError {
	attempt.Log("error: " + callErr.Error())
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

	if stopped {
		queue.queueManager.notifyStopAttempt(attempt)
	}

	return err
}
