package queue

import (
	"fmt"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
	"math/rand"
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

	attempt.Info = &AttemptInfoCall{}

	go queue.run(attempt)

	return nil
}

func (queue *IVRQueue) run(attempt *Attempt) {

	defer queue.queueManager.LeavingMember(attempt, queue)

	legB := fmt.Sprintf("1@webitel.lo") //TODO

	dst := attempt.resource.Gateway().Endpoint(attempt.Destination())

	callRequest := &model.CallRequest{
		Endpoints:    []string{dst},
		CallerNumber: attempt.Destination(),
		CallerName:   attempt.Name(),
		Timeout:      queue.Timeout(),
		Variables: model.UnionStringMaps(
			queue.Variables(),
			attempt.Variables(),
			map[string]string{
				"sip_route_uri":             queue.SipRouterAddr(), //"$${outbound_sip_proxy}",
				"sip_h_X-Webitel-Direction": "outbound",
				//"sip_h_X-Webitel-Domain":               "10.10.10.144",
				"absolute_codec_string":                "PCMU",
				model.CALL_IGNORE_EARLY_MEDIA_VARIABLE: "true",
				model.CALL_DIRECTION_VARIABLE:          model.CALL_DIRECTION_DIALER,
				model.CALL_DOMAIN_VARIABLE:             queue.Domain(),
				model.QUEUE_ID_FIELD:                   fmt.Sprintf("%d", queue.id),
				model.QUEUE_NAME_FIELD:                 queue.name,
				model.QUEUE_TYPE_NAME_FIELD:            queue.TypeName(),
				model.QUEUE_SIDE_FIELD:                 model.QUEUE_SIDE_MEMBER,
				model.QUEUE_MEMBER_ID_FIELD:            fmt.Sprintf("%d", attempt.MemberId()),
				model.QUEUE_ATTEMPT_ID_FIELD:           fmt.Sprintf("%d", attempt.Id()),
				model.QUEUE_RESOURCE_ID_FIELD:          fmt.Sprintf("%d", attempt.resource.Id()),
			},
		),
		Applications: make([]*model.CallRequestApplication, 0, 4),
	}

	err := queue.queueManager.SetAttemptState(attempt.Id(), model.MEMBER_STATE_ORIGINATE)
	if err != nil {
		panic(err.Error()) //TODO
	}

	if queue.RecordCallEnabled() {
		queue.SetRecordCall(callRequest, model.CALL_RECORD_SESSION_TEMPLATE)
	}

	if queue.amd != nil && queue.amd.Enabled {
		queue.SetAmdCall(
			callRequest,
			queue.amd,
			fmt.Sprintf("%s::%s", model.CALL_TRANSFER_APPLICATION, legB),
			fmt.Sprintf("%s::%s", model.CALL_HANGUP_APPLICATION, model.CALL_HANGUP_NORMAL_UNSPECIFIED),
			fmt.Sprintf("%s::%s", model.CALL_HANGUP_APPLICATION, model.CALL_HANGUP_NORMAL_UNSPECIFIED),
		)
	} else {
		slleps := []string{
			"1000",
			"10000",
			"6000",
			"10000",
			"5000",
			"7000",
			"60000",
			"120000",
		}
		callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
			AppName: "sleep",
			Args:    slleps[rand.Intn(len(slleps))],
		})
	}

	call := queue.NewCallUseResource(callRequest, attempt.resource)
	call.Invite()
	if call.Err() != nil {
		queue.CallError(attempt, call.Err(), call.HangupCause())
		return
	}

	defer func() {
		if call.Err() != nil {
			queue.queueManager.SetResourceError(attempt.resource, fmt.Sprintf("%d", call.HangupCauseCode()))
		}
	}()

	wlog.Debug(fmt.Sprintf("Create call %s for member %s attemptId %v", call.Id(), attempt.Name(), attempt.Id()))

	var calling = true

	for calling {
		select {
		case state := <-call.State():
			switch state {
			case call_manager.CALL_STATE_RINGING:
				queue.queueManager.SetBridged(attempt, model.NewString(call.Id()), nil)
			}
		case <-call.HangupChan():
			calling = false
		}
	}

	if call.HangupCause() == "" {
		queue.StopAttemptWithCallDuration(attempt, model.MEMBER_CAUSE_SUCCESSFUL, 0) //TODO
	} else {
		queue.StopAttemptWithCallDuration(attempt, call.HangupCause(), 0) //TODO
	}
}
