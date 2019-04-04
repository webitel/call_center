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

func (voice *VoiceBroadcastQueue) FoundAgentForAttempt(attempt *Attempt) {
	panic(`Broadcast queue not reserve agents`)
}

func (voice *VoiceBroadcastQueue) JoinAttempt(attempt *Attempt) {
	attempt.info = &AttemptInfoCall{}

	if attempt.member.ResourceId == nil || attempt.member.ResourceUpdatedAt == nil {
		//todo
		panic(123)
	}

	r, e := voice.resourceManager.Get(*attempt.member.ResourceId, *attempt.member.ResourceUpdatedAt)
	if e != nil {
		//todo
		panic(e.Error())
	}

	if attempt.GetCommunicationPattern() == nil {
		//todo
		panic("no pattern")
	}

	endpoint, e := voice.resourceManager.GetEndpoint(*attempt.GetCommunicationPattern())

	if e != nil {
		//TODO
		panic(e)
	}

	go voice.makeCall(attempt, r.(ResourceObject), endpoint)
}

func (voice *VoiceBroadcastQueue) makeCall(attempt *Attempt, resource ResourceObject, endpoint *Endpoint) {
	dst := endpoint.Parse(resource.GetDialString(), attempt.Destination())
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
			resource.Variables(),
			voice.Variables(),
			attempt.Variables(),
			map[string]string{
				"absolute_codec_string":                "PCMU",
				model.CALL_IGNORE_EARLY_MEDIA_VARIABLE: "true",
				model.CALL_DIRECTION_VARIABLE:          model.CALL_DIRECTION_DIALER,
				model.CALL_DOMAIN_VARIABLE:             voice.Domain(),
				model.QUEUE_NODE_ID_FIELD:              voice.queueManager.GetNodeId(),
				model.QUEUE_ID_FIELD:                   fmt.Sprintf("%d", voice.id),
				model.QUEUE_NAME_FIELD:                 voice.name,
				model.QUEUE_SIDE_FIELD:                 model.QUEUE_SIDE_MEMBER,
				model.QUEUE_MEMBER_ID_FIELD:            fmt.Sprintf("%d", attempt.MemberId()),
				model.QUEUE_ATTEMPT_ID_FIELD:           fmt.Sprintf("%d", attempt.Id()),
				model.QUEUE_RESOURCE_ID_FIELD:          fmt.Sprintf("%d", resource.Id()),
				model.QUEUE_ROUTING_ID_FIELD:           fmt.Sprintf("%d", attempt.GetCommunicationRoutingId()),
			},
		),
		Applications: make([]*model.CallRequestApplication, 0, 4),
	}

	if voice.RecordCall() {
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
	uuid, cause, err := voice.NewCallToMember(callRequest, attempt.GetCommunicationRoutingId(), resource)
	if err != nil {
		voice.CallError(attempt, err, cause)
		voice.queueManager.LeavingMember(attempt, voice)
		return
	}

	mlog.Debug(fmt.Sprintf("Create call %s for member %s attemptId %v", uuid, attempt.Name(), attempt.Id()))

	err = voice.queueManager.SetBridged(attempt, model.NewString(uuid), nil)

	if err != nil {
		//todo
		panic(err.Error())
	}
}

func (voice *VoiceBroadcastQueue) SetHangupCall(attempt *Attempt, event Event) {
	cause, _ := event.GetVariable(model.CALL_HANGUP_CAUSE_VARIABLE)

	if cause == "" {
		//TODO
		cause = model.MEMBER_CAUSE_SUCCESSFUL
	}

	voice.StopAttemptWithCallDuration(attempt, cause, 10) //TODO
	voice.queueManager.LeavingMember(attempt, voice)
}
