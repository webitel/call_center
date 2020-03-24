package queue

import (
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
)

type ProgressiveCallQueue struct {
	CallingQueue
}

func NewProgressiveCallQueue(callQueue CallingQueue) QueueObject {
	return &ProgressiveCallQueue{
		CallingQueue: callQueue,
	}
}

func (queue *ProgressiveCallQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	fmt.Println(attempt.Id(), " >>>> ", attempt.agent.Id())

	if attempt.resource == nil {
		return NewErrorResourceRequired(queue, attempt)
	}

	if attempt.agent == nil {
		return NewErrorAgentRequired(queue, attempt)
	}

	destination := "123"

	team, err := queue.GetTeam(attempt)
	if err != nil {
		return err
	}

	go queue.run(team, attempt, attempt.Agent(), destination)

	return nil
}

func (queue *ProgressiveCallQueue) run(team *agentTeam, attempt *Attempt, agent agent_manager.AgentObject, destination string) {
	defer queue.queueManager.LeavingMember(attempt, queue)

	callRequest := &model.CallRequest{
		Endpoints:    []string{"null"}, //agent.GetCallEndpoints(), // []string{dst},
		CallerNumber: attempt.Destination(),
		CallerName:   attempt.Name(),
		Timeout:      queue.Timeout(),
		Variables: model.UnionStringMaps(
			attempt.resource.Variables(),
			queue.Variables(),
			attempt.ExportVariables(),
			map[string]string{
				"sip_h_X-Webitel-Direction": "internal",
				//"sip_h_X-Webitel-Domain":               "10.10.10.144",
				"absolute_codec_string":                "PCMU",
				model.CALL_IGNORE_EARLY_MEDIA_VARIABLE: "true",
				model.CALL_DIRECTION_VARIABLE:          model.CALL_DIRECTION_DIALER,
				model.CallVariableDomainName:           queue.Domain(),
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

	callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
		AppName: "park",
		Args:    "",
	})

	call := queue.NewCallUseResource(callRequest, attempt.resource)
	call.Invite()

	var calling = true

	for calling {
		select {
		case state := <-call.State():
			switch state {
			case call_manager.CALL_STATE_ACCEPT:
				if cnt, err := queue.queueManager.store.Agent().ConfirmAttempt(agent.Id(), attempt.Id()); err != nil {
					call.Hangup(model.CALL_HANGUP_NORMAL_UNSPECIFIED) // TODO
				} else if cnt > 0 {
					//agent.SetStateTalking(0)
					call.Hangup(model.CALL_HANGUP_NORMAL_CLEARING)
					agent.SetStateReporting(50)
				}
			case call_manager.CALL_STATE_BRIDGE:
				agent.SetStateTalking()
			}
		case result := <-attempt.cancel:
			switch result {
			case model.MEMBER_CAUSE_CANCEL:
				call.Hangup(model.CALL_HANGUP_LOSE_RACE)
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
