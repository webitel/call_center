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

	//if err := queue.SetAttemptResult(result); err != nil {
	//	wlog.Error(fmt.Sprintf("attempt [%d] set result error: %s", attempt.Id(), err.Error()))
	//}

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

	dst := attempt.resource.Gateway().Endpoint(attempt.Destination())
	var callerIdNumber string

	if attempt.destination.Display != nil && *attempt.destination.Display != "" {
		callerIdNumber = *attempt.destination.Display
	} else {
		callerIdNumber = attempt.resource.GetDisplay()
	}

	callRequest := &model.CallRequest{
		Endpoints:    []string{dst},
		CallerNumber: attempt.Destination(),
		CallerName:   attempt.Name(),
		Timeout:      queue.Timeout(),
		Destination:  attempt.Destination(),
		Variables: model.UnionStringMaps(
			queue.Variables(),
			attempt.ExportVariables(),
			map[string]string{
				model.CallVariableDomainName:  queue.Domain(),
				model.CallVariableDomainId:    fmt.Sprintf("%v", queue.DomainId()),
				model.CallVariableGatewayId:   fmt.Sprintf("%v", attempt.resource.Gateway().Id),
				model.CallVariableGatewayName: fmt.Sprintf("%v", attempt.resource.Gateway().Name),

				"hangup_after_bridge": "true",

				"sip_h_X-Webitel-Display-Direction": "outbound",
				"sip_h_X-Webitel-Origin":            "request",
				"wbt_destination":                   attempt.Destination(),
				"wbt_from_id":                       fmt.Sprintf("%v", attempt.resource.Gateway().Id), //FIXME gateway id ?
				"wbt_from_number":                   callerIdNumber,                                   //display number
				"wbt_from_name":                     attempt.resource.Gateway().Name,
				"wbt_from_type":                     "gateway",

				"wbt_to_id":     fmt.Sprintf("%v", attempt.MemberId()),
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
				model.QUEUE_MEMBER_ID_FIELD:   fmt.Sprintf("%d", attempt.MemberId()),
				model.QUEUE_ATTEMPT_ID_FIELD:  fmt.Sprintf("%d", attempt.Id()),
				model.QUEUE_RESOURCE_ID_FIELD: fmt.Sprintf("%d", attempt.resource.Id()),
			},
		),
	}

	call := queue.NewCallUseResource(callRequest, attempt.resource)
	info.fromCall = call
	call.Invite()
	if call.Err() != nil {
		return
	}

	wlog.Debug(fmt.Sprintf("calling %s for member %s attemptId %v", call.Id(), attempt.Name(), attempt.Id()))

	var calling = true

	for calling {
		select {
		case state := <-call.State():
			switch state {
			case call_manager.CALL_STATE_JOIN:
				call.Hangup("USER_BUSY", false)
			//case call_manager.CALL_STATE_LEAVING:

			default:
				fmt.Println(state.String())
			}
		case <-call.HangupChan():
			calling = false
		}
	}
}
