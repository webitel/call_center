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

func (queue *IVRQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	if attempt.resource == nil {
		return NewErrorResourceRequired(queue, attempt)
	}

	go queue.run(attempt)

	return nil
}

func (queue *IVRQueue) run(attempt *Attempt) {
	info := queue.GetCallInfoFromAttempt(attempt)

	dst := attempt.resource.Gateway().Endpoint(attempt.Destination())
	var callerIdNumber string

	// FIXME display
	if attempt.communication.Display != nil && *attempt.communication.Display != "" {
		callerIdNumber = *attempt.communication.Display
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

				"wbt_to_id":     fmt.Sprintf("%d", attempt.MemberId()),
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
		Applications: []*model.CallRequestApplication{
			{
				AppName: "answer",
				Args:    "",
			},
			{
				AppName: "sleep",
				Args:    "1000",
			},
			{
				AppName: "hangup",
				Args:    "",
			},
		},
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
			case call_manager.CALL_STATE_RINGING:
			case call_manager.CALL_STATE_ACCEPT:
			case call_manager.CALL_STATE_BRIDGE:
				fmt.Println(">>> ", state.String())

			default:
				fmt.Println(state.String())
			}
		case <-call.HangupChan():
			calling = false
		}
	}

	queue.queueManager.Abandoned(attempt)
	queue.queueManager.LeavingMember(attempt, queue)
}
