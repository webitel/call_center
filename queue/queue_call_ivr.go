package queue

import (
	"fmt"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
)

type IVRQueue struct {
	CallingQueue
	amd *model.QueueAmdSettings
}

func NewIVRQueue(callQueue CallingQueue, amd *model.QueueAmdSettings) QueueObject {
	return &IVRQueue{
		CallingQueue: callQueue,
		amd:          amd,
	}
}

func (queue *IVRQueue) reporting(attempt *Attempt) {
	attempt.SetState(model.MEMBER_STATE_POST_PROCESS)

	info := queue.GetCallInfoFromAttempt(attempt)
	wlog.Debug(fmt.Sprintf("attempt[%d] start reporting", attempt.Id()))
	result := &model.AttemptResult{}
	result.Id = attempt.Id()
	if info.fromCall != nil {
		result.LegAId = model.NewString(info.fromCall.Id())
		result.OfferingAt = info.fromCall.OfferingAt()
		result.AnsweredAt = info.fromCall.AcceptAt()

		if info.fromCall.BillSeconds() > 0 {
			result.Result = model.MEMBER_CAUSE_SUCCESSFUL
			result.BridgedAt = info.fromCall.BridgeAt()
		} else {
			result.Result = model.MEMBER_CAUSE_ABANDONED
		}
		result.HangupAt = info.fromCall.HangupAt()
	} else {
		result.HangupAt = model.GetMillis()
	}

	result.State = model.MEMBER_STATE_END

	attempt.SetResult(model.NewString(result.Result))

	if err := queue.SetAttemptResult(result); err != nil {
		wlog.Error(fmt.Sprintf("attempt [%d] set result error: %s", attempt.Id(), err.Error()))
	}

	wlog.Debug(fmt.Sprintf("attempt[%d] reporting: %v", attempt.Id(), result))
	queue.queueManager.LeavingMember(attempt, queue)
}

func (queue *IVRQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	if attempt.resource == nil {
		return NewErrorResourceRequired(queue, attempt)
	}

	attempt.Info = &AttemptInfoCall{}

	go queue.run(attempt)

	return nil
}

func (queue *IVRQueue) run(attempt *Attempt) {
	defer queue.reporting(attempt)
	info := queue.GetCallInfoFromAttempt(attempt)

	//dst := attempt.resource.Gateway().Endpoint(attempt.Destination())
	callRequest := &model.CallRequest{
		Endpoints:    []string{"null"},
		CallerNumber: attempt.Destination(),
		CallerName:   attempt.Name(),
		Timeout:      queue.Timeout(),
		Destination:  attempt.Destination(),
		Context:      "call_center",
		Variables: model.UnionStringMaps(
			queue.Variables(),
			attempt.Variables(),
			map[string]string{
				"sip_route_uri":               queue.SipRouterAddr(),
				"cc_destination":              attempt.Destination(),
				model.CALL_DIRECTION_VARIABLE: model.CALL_DIRECTION_DIALER,
				model.CALL_DOMAIN_VARIABLE:    queue.Domain(),
				model.QUEUE_ID_FIELD:          fmt.Sprintf("%d", queue.id),
				model.QUEUE_NAME_FIELD:        queue.name,
				model.QUEUE_TYPE_NAME_FIELD:   queue.TypeName(),
				model.QUEUE_SIDE_FIELD:        model.QUEUE_SIDE_MEMBER,
				model.QUEUE_MEMBER_ID_FIELD:   fmt.Sprintf("%d", attempt.MemberId()),
				model.QUEUE_ATTEMPT_ID_FIELD:  fmt.Sprintf("%d", attempt.Id()),
				model.QUEUE_RESOURCE_ID_FIELD: fmt.Sprintf("%d", attempt.resource.Id()),
			},
		),
		//Applications: make([]*model.CallRequestApplication, 0, 4),
	}

	err := queue.queueManager.SetAttemptState(attempt.Id(), model.MEMBER_STATE_ORIGINATE)
	if err != nil {
		panic(err.Error()) //TODO
	}

	call := queue.NewCallUseResource(callRequest, attempt.resource)
	info.fromCall = call
	call.Invite()
	if call.Err() != nil {
		return
	}

	wlog.Debug(fmt.Sprintf("Create call %s for member %s attemptId %v", call.Id(), attempt.Name(), attempt.Id()))

	var calling = true

	for calling {
		select {
		case state := <-call.State():
			switch state {
			case call_manager.CALL_STATE_PARK:

				fmt.Println("PARK")
			case call_manager.CALL_STATE_RINGING:
				queue.queueManager.SetAttemptState(attempt.Id(), model.MEMBER_STATE_ACTIVE)
				queue.queueManager.SetBridged(attempt, model.NewString(call.Id()), nil)
			}
		case <-call.HangupChan():
			calling = false
		}
	}
}
