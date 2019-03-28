package queue

import "github.com/webitel/call_center/model"

type CallingQueueObject interface {
	SetHangupCall(attempt *Attempt, event Event)
}

type CallingQueue struct {
	BaseQueue
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
