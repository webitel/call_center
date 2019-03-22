package queue

import (
	"fmt"
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
)

type VoiceBroadcastQueue struct {
	CallingQueue
	settings model.QueueVoiceSettings
}

func NewVoiceBroadcastQueue(callQueue CallingQueue, settings *model.Queue) QueueObject {
	return &VoiceBroadcastQueue{
		CallingQueue: callQueue,
		settings:     model.QueueVoiceSettingsFromBytes(settings.Payload),
	}
}

func (voice *VoiceBroadcastQueue) FoundAgentForAttempt(attempt *Attempt) {
	panic(`Broadcast queue not reserve agents`)
}

func (voice *VoiceBroadcastQueue) AddMemberAttempt(attempt *Attempt) {
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

	info, err := voice.queueManager.Originate(attempt)
	if err != nil {
		panic(err.Error())
	}

	dst := endpoint.Parse(resource.GetDialString(), info.Number)
	attempt.Log(`dial string: ` + dst)

	/*
		TODO: timeout: NO_ANSWER vs PROGRESS_TIMEOUT ?
	*/
	callRequest := &model.CallRequest{
		Endpoints:    []string{dst},
		CallerNumber: info.Number,
		CallerName:   info.Name,
		Timeout:      voice.Timeout(),
		//Strategy: model.CALL_STRATEGY_MULTIPLE,
		Variables: model.UnionStringMaps(
			resource.Variables(),
			voice.Variables(),
			map[string]string{
				"absolute_codec_string":                     "PCMU",
				model.CALL_IGNORE_EARLY_MEDIA_VARIABLE_NAME: "true",
				model.CALL_DIRECTION_VARIABLE_NAME:          model.CALL_DIRECTION_DIALER,
				model.CALL_DOMAIN_VARIABLE_NAME:             "10.10.10.25",
				model.QUEUE_NODE_ID_FIELD:                   voice.queueManager.GetNodeId(),
				model.QUEUE_ID_FIELD:                        fmt.Sprintf("%d", voice.id),
				model.QUEUE_NAME_FIELD:                      voice.name,
				model.QUEUE_SIDE_FIELD:                      model.QUEUE_SIDE_MEMBER,
				model.QUEUE_MEMBER_ID_FIELD:                 fmt.Sprintf("%d", attempt.member.Id),
				model.QUEUE_ATTEMPT_ID_FIELD:                fmt.Sprintf("%d", attempt.Id()),
				model.QUEUE_RESOURCE_ID_FIELD:               fmt.Sprintf("%d", resource.Id()),
			},
		),
		//Destination: "1000",
		//Context:     "default",
		Extensions: []*model.CallRequestExtension{
			{
				AppName: "bridge",
				Args:    "user/1000@10.10.10.25",
			},
			{
				AppName: "hangup",
			},
		},
	}

	resource.Take() // rps
	uuid, cause, err := voice.queueManager.app.NewCall(callRequest)
	if err != nil {
		voice.queueManager.LeavingMember(attempt, voice)
		voice.queueManager.SetAttemptError(attempt, model.MEMBER_STATE_END, cause)
		return
	}

	mlog.Debug(fmt.Sprintf("Create call %s for member id %v", uuid, attempt.Id()))

	err = voice.queueManager.SetBridged(attempt, model.NewString(uuid), nil)
	if err != nil {
		//todo
		panic(err.Error())
	}
}

func (voice *VoiceBroadcastQueue) SetHangupCall(attempt *Attempt) {
	i, err := voice.queueManager.StopAttempt(attempt.Id(), 1, model.MEMBER_STATE_END, model.GetMillis(), model.MEMBER_CAUSE_SUCCESSFUL)
	if err != nil {
		//todo
		panic("todo")
	} else if i != nil {
		//fmt.Println(i)
	}

	voice.queueManager.LeavingMember(attempt, voice)
}
