package queue

import (
	"fmt"
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
)

type VoiceBroadcastQueue struct {
	CallingQueue
	amd *model.QueueAmdSettings
}

func NewVoiceBroadcastQueue(callQueue CallingQueue, amd *model.QueueAmdSettings) QueueObject {
	return &VoiceBroadcastQueue{
		CallingQueue: callQueue,
		amd:          amd,
	}
}

func (voice *VoiceBroadcastQueue) RouteAgentToAttempt(attempt *Attempt) {
	panic(`Broadcast queue not reserve agents`)
}

func (voice *VoiceBroadcastQueue) JoinAttempt(attempt *Attempt) {
	Assert(attempt.resource)

	attempt.Info = &AttemptInfoCall{}

	if attempt.GetCommunicationPattern() == nil {
		//todo
		panic("no pattern")
	}

	endpoint, e := voice.resourceManager.GetEndpoint(*attempt.GetCommunicationPattern())

	if e != nil {
		//TODO
		panic(e)
	}

	go voice.makeCall(attempt, endpoint)
}

func (voice *VoiceBroadcastQueue) makeCall(attempt *Attempt, endpoint *Endpoint) {
	dst := endpoint.Parse(attempt.resource.GetDialString(), attempt.Destination())
	attempt.Log(`dial string: ` + dst)
	//legB := fmt.Sprintf("100 XML default '%s' '%s'", "100", "100") //TODO
	legB := fmt.Sprintf("999 XML default '%s' '%s'", "100", "100") //TODO

	info := voice.GetCallInfoFromAttempt(attempt)

	/*
		TODO: timeout: NO_ANSWER vs PROGRESS_TIMEOUT ?
	*/
	callRequest := &model.CallRequest{
		Endpoints:    []string{"sofia/external/dialer-12@10.10.10.25:5080"},
		CallerNumber: attempt.Destination(),
		CallerName:   attempt.Name(),
		Timeout:      voice.Timeout(),
		Variables: model.UnionStringMaps(
			attempt.resource.Variables(),
			voice.Variables(),
			attempt.Variables(),
			map[string]string{
				"absolute_codec_string":                "PCMU",
				model.CALL_IGNORE_EARLY_MEDIA_VARIABLE: "true",
				model.CALL_DIRECTION_VARIABLE:          model.CALL_DIRECTION_DIALER,
				model.CALL_DOMAIN_VARIABLE:             voice.Domain(),
				model.QUEUE_ID_FIELD:                   fmt.Sprintf("%d", voice.id),
				model.QUEUE_NAME_FIELD:                 voice.name,
				model.QUEUE_TYPE_NAME_FIELD:            voice.TypeName(),
				model.QUEUE_SIDE_FIELD:                 model.QUEUE_SIDE_MEMBER,
				model.QUEUE_MEMBER_ID_FIELD:            fmt.Sprintf("%d", attempt.MemberId()),
				model.QUEUE_ATTEMPT_ID_FIELD:           fmt.Sprintf("%d", attempt.Id()),
				model.QUEUE_RESOURCE_ID_FIELD:          fmt.Sprintf("%d", attempt.resource.Id()),
				model.QUEUE_ROUTING_ID_FIELD:           fmt.Sprintf("%d", attempt.GetCommunicationRoutingId()),
			},
		),
		Applications: make([]*model.CallRequestApplication, 0, 4),
	}

	if voice.RecordCallEnabled() {
		voice.SetRecordCall(callRequest, model.CALL_RECORD_SESSION_TEMPLATE)
		info.UseRecordings = true
	}

	if voice.amd != nil && voice.amd.Enabled {
		voice.SetAmdCall(
			callRequest,
			voice.amd,
			fmt.Sprintf("%s::%s", model.CALL_TRANSFER_APPLICATION, legB),
			fmt.Sprintf("%s::%s", model.CALL_HANGUP_APPLICATION, model.CALL_HANGUP_NORMAL_UNSPECIFIED),
			fmt.Sprintf("%s::%s", model.CALL_HANGUP_APPLICATION, model.CALL_HANGUP_NORMAL_UNSPECIFIED),
		)
		info.UseAmd = true
	} else {
		callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
			AppName: model.CALL_TRANSFER_APPLICATION,
			Args:    legB,
		})
	}

	info.LegAUri = dst
	info.LegBUri = legB
	call := voice.NewCallToMember(callRequest, attempt.GetCommunicationRoutingId(), attempt.resource)
	if call.Error() != nil {
		voice.CallError(attempt, call.Error(), call.HangupCause())
		voice.queueManager.LeavingMember(attempt, voice)
		return
	}

	mlog.Debug(fmt.Sprintf("Create call %s for member %s attemptId %v", call.Id(), attempt.Name(), attempt.Id()))

	err := voice.queueManager.SetBridged(attempt, model.NewString(call.Id()), nil)

	if err != nil {
		//todo
		panic(err.Error())
	}
	call.WaitHangup()

	if call.HangupCause() == "" {
		voice.StopAttemptWithCallDuration(attempt, model.MEMBER_CAUSE_SUCCESSFUL, 10) //TODO
	} else {
		voice.StopAttemptWithCallDuration(attempt, call.HangupCause(), 10) //TODO
	}

	voice.queueManager.LeavingMember(attempt, voice)
}