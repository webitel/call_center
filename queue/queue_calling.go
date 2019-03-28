package queue

import (
	"github.com/webitel/call_center/model"
)

type CallingQueueObject interface {
	SetHangupCall(attempt *Attempt, event Event)
}

type CallingQueue struct {
	BaseQueue
	params model.QueueDialingSettings
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
