package queue

import (
	"fmt"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
)

type PredictCallQueue struct {
	//ProgressiveCallQueue
	InboundQueue
	CallingQueue
	Amd *model.QueueAmdSettings
}

func NewPredictCallQueue(callQueue CallingQueue, settings ProgressiveCallQueueSettings) QueueObject {
	return &PredictCallQueue{
		CallingQueue: callQueue,
		InboundQueue: InboundQueue{
			CallingQueue: callQueue,
			props: model.QueueInboundSettings{
				DiscardAbandonedAfter: 0,
				TimeBaseScore:         "",
				MaxWaitWithNoAgent:    0,
				MaxCallPerAgent:       0,
				AllowGreetingAgent:    false,
				MaxWaitTime:           60,
			},
		},
		//ProgressiveCallQueue: ProgressiveCallQueue{
		//	CallingQueue:                 callQueue,
		//	ProgressiveCallQueueSettings: settings,
		//},
	}
}

func (queue *PredictCallQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	if attempt.resource == nil {
		return NewErrorResourceRequired(queue, attempt)
	}

	team, err := queue.GetTeam(attempt)
	if err != nil {
		return err
	}

	go queue.runPark(attempt, team)

	return nil
}

func (queue *PredictCallQueue) runPark(attempt *Attempt, team *agentTeam) {

	if !queue.queueManager.DoDistributeSchema(&queue.BaseQueue, attempt) {
		queue.queueManager.LeavingMember(attempt)
		return
	}

	dst := attempt.resource.Gateway().Endpoint(attempt.Destination())
	var callerIdNumber string

	// FIXME display
	if attempt.communication.Display != nil && *attempt.communication.Display != "" {
		callerIdNumber = *attempt.communication.Display
	} else {
		callerIdNumber = attempt.resource.GetDisplay()
	}

	callRequest := &model.CallRequest{
		Id:           attempt.MemberCallId(),
		Endpoints:    []string{dst},
		CallerNumber: attempt.Destination(),
		CallerName:   attempt.Name(),
		//Timeout:      queue.OriginateTimeout,
		Destination: attempt.Destination(),
		Variables: model.UnionStringMaps(
			queue.Variables(),
			attempt.ExportVariables(),
			map[string]string{
				model.CallVariableDomainName: queue.Domain(),
				model.CallVariableDomainId:   fmt.Sprintf("%v", queue.DomainId()),
				model.CallVariableGatewayId:  fmt.Sprintf("%v", attempt.resource.Gateway().Id),

				"hangup_after_bridge":    "true",
				"ignore_display_updates": "true",
				//"park_timeout":           "5",

				"sip_h_X-Webitel-Display-Direction": "outbound",
				"sip_h_X-Webitel-Origin":            "request",
				"wbt_destination":                   attempt.Destination(),
				"wbt_from_id":                       fmt.Sprintf("%v", attempt.resource.Gateway().Id), //FIXME gateway id ?
				"wbt_from_number":                   callerIdNumber,
				"wbt_from_name":                     attempt.resource.Gateway().Name,
				"wbt_from_type":                     "gateway",

				"wbt_to_id":     fmt.Sprintf("%d", *attempt.MemberId()),
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
				model.QUEUE_MEMBER_ID_FIELD:   fmt.Sprintf("%v", *attempt.MemberId()),
				model.QUEUE_ATTEMPT_ID_FIELD:  fmt.Sprintf("%d", attempt.Id()),
				model.QUEUE_RESOURCE_ID_FIELD: fmt.Sprintf("%d", attempt.resource.Id()),
			},
		),
		Applications: make([]*model.CallRequestApplication, 0, 2),
	}

	mCall := queue.NewCallUseResource(callRequest, attempt.resource)
	//var agentCall call_manager.Call

	//if queue.Recordings {
	//	callRequest.Applications = append(callRequest.Applications, queue.GetRecordingsApplication(mCall))
	//}

	if !queue.SetAmdCall(callRequest, queue.Amd, "park") {
		callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
			AppName: "park",
		})
	}

	mCall.Invite()

	var calling = true

	for calling {
		select {
		case state := <-mCall.State():
			switch state {
			case call_manager.CALL_STATE_ACCEPT, call_manager.CALL_STATE_DETECT_AMD:
				// FIXME
				if (state == call_manager.CALL_STATE_ACCEPT && queue.Amd != nil && queue.Amd.Enabled) || (state == call_manager.CALL_STATE_DETECT_AMD && !mCall.IsHuman()) {
					continue
				}

				fmt.Println("START INB")
				queue.InboundQueue.run(attempt, mCall, team)

				fmt.Println("END INB")

				return
				//mCall.Hangup("", false)
			}
		case <-mCall.HangupChan():
			calling = false
		}
	}

	if mCall.AcceptAt() > 0 && int((mCall.HangupAt()-mCall.AcceptAt())/1000) > int(100) {
		queue.queueManager.teamManager.store.Member().SetAttemptResult(attempt.Id(), "success", "", 0)
	} else {
		queue.queueManager.SetAttemptAbandonedWithParams(attempt, 100, 60)
	}

	queue.queueManager.LeavingMember(attempt)

}
