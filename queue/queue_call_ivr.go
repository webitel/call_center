package queue

import (
	"encoding/json"
	"fmt"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
)

type QueueIVRSettings struct {
	Recordings         bool                    `json:"recordings"`
	Amd                *model.QueueAmdSettings `json:"amd"`
	MinDuration        uint                    `json:"min_duration"`
	MaxAttempts        uint                    `json:"max_attempts"`
	OriginateTimeout   int                     `json:"originate_timeout"`
	WaitBetweenRetries uint64                  `json:"wait_between_retries"`
}

type IVRQueue struct {
	CallingQueue
	QueueIVRSettings
}

func QueueIVRSettingsFromBytes(data []byte) QueueIVRSettings {
	var settings QueueIVRSettings
	json.Unmarshal(data, &settings)
	return settings
}

func NewIVRQueue(callQueue CallingQueue, settings QueueIVRSettings) QueueObject {
	return &IVRQueue{
		CallingQueue:     callQueue,
		QueueIVRSettings: settings,
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

	if !queue.queueManager.DoDistributeSchema(&queue.BaseQueue, attempt) {
		queue.queueManager.LeavingMember(attempt, queue)
		return
	}

	dst := attempt.resource.Gateway().Endpoint(attempt.Destination())
	var callerIdNumber string

	if attempt.communication.Display != nil && *attempt.communication.Display != "" {
		callerIdNumber = *attempt.communication.Display
	} else {
		callerIdNumber = attempt.resource.GetDisplay()
	}

	callRequest := &model.CallRequest{
		Endpoints:    []string{dst},
		CallerNumber: attempt.Destination(),
		CallerName:   attempt.Name(),
		Timeout:      uint16(queue.OriginateTimeout),
		Destination:  attempt.Destination(),
		Variables: model.UnionStringMaps(
			queue.Variables(),
			attempt.resource.Variables(),
			attempt.ExportVariables(),
			map[string]string{
				model.CallVariableDomainName: queue.Domain(),
				model.CallVariableDomainId:   fmt.Sprintf("%v", queue.DomainId()),
				model.CallVariableGatewayId:  fmt.Sprintf("%v", attempt.resource.Gateway().Id),

				"hangup_after_bridge":   "true",
				"ignore_early_media":    "true",
				"absolute_codec_string": "pcma,pcmu",

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
				model.QUEUE_MEMBER_ID_FIELD:   fmt.Sprintf("%d", *attempt.MemberId()),
				model.QUEUE_ATTEMPT_ID_FIELD:  fmt.Sprintf("%d", attempt.Id()),
				model.QUEUE_RESOURCE_ID_FIELD: fmt.Sprintf("%d", attempt.resource.Id()),
			},
		),
		Applications: make([]*model.CallRequestApplication, 0, 1),
	}

	call := queue.NewCallUseResource(callRequest, attempt.resource)

	if queue.Recordings {
		callRequest.Applications = append(callRequest.Applications, queue.GetRecordingsApplication(call))
	}

	if !queue.SetAmdCall(callRequest, queue.Amd, queue.CallManager().GetFlowUri()) {
		callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
			AppName: "socket",
			Args:    "$${acr_srv}",
		})
	}

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
				_, err := queue.queueManager.store.Member().
					SetAttemptOffering(attempt.Id(), nil, nil, model.NewString(call.Id()), &dst, &callerIdNumber)
				if err != nil {
					wlog.Error(err.Error())
				}

			case call_manager.CALL_STATE_DETECT_AMD, call_manager.CALL_STATE_ACCEPT:
				// FIXME
				if (state == call_manager.CALL_STATE_ACCEPT && queue.Amd != nil && queue.Amd.Enabled) || (state == call_manager.CALL_STATE_DETECT_AMD && !call.IsHuman()) {
					continue
				}

				_, err := queue.queueManager.store.Member().SetAttemptBridged(attempt.Id())
				if err != nil {
					wlog.Error(err.Error())
				}

			case call_manager.CALL_STATE_HANGUP:
				calling = false
			default:
				attempt.Log(fmt.Sprintf("set state %s", state))
			}
		}
	}

	if call.AcceptAt() > 0 && int((call.HangupAt()-call.AcceptAt())/1000) > int(queue.MinDuration) {
		queue.queueManager.teamManager.store.Member().SetAttemptResult(attempt.Id(), "success", 0,
			"", 0)
	} else {
		queue.queueManager.SetAttemptAbandonedWithParams(attempt, queue.MaxAttempts, queue.WaitBetweenRetries)
	}

	queue.queueManager.LeavingMember(attempt, queue)
}
