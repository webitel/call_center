package queue

import (
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
)

type PreviewCallQueue struct {
	CallingQueue
}

func NewPreviewCallQueue(callQueue CallingQueue) QueueObject {
	return &PreviewCallQueue{
		CallingQueue: callQueue,
	}
}

func (preview *PreviewCallQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	//if attempt.resource == nil {
	//	return NewErrorResourceRequired(preview, attempt)
	//}
	//
	//if attempt.agent == nil {
	//	return NewErrorAgentRequired(preview, attempt)
	//}
	//
	//if attempt.GetCommunicationPattern() == nil {
	//	return NewErrorCommunicationPatternRequired(preview, attempt)
	//}
	//
	//endpoint, err := preview.resourceManager.GetEndpoint(*attempt.GetCommunicationPattern())
	//if err != nil {
	//	return err
	//}
	//
	//destination := endpoint.Parse(attempt.resource.GetDialString(), attempt.Destination())
	//
	//team, err := preview.GetTeam(attempt)
	//if err != nil {
	//	return err
	//}
	//
	//go preview.run(team, attempt, attempt.Agent(), destination)

	return nil
}

func (queue *PreviewCallQueue) run(team *agentTeam, attempt *Attempt, agent agent_manager.AgentObject, destination string) {

	defer queue.queueManager.LeavingMember(attempt, queue)

	callRequest := &model.CallRequest{
		Endpoints:    agent.GetCallEndpoints(), //agent.GetCallEndpoints(), //agent.GetCallEndpoints(), // []string{"null"},
		CallerName:   attempt.Name(),
		CallerNumber: attempt.Destination(),
		Timeout:      team.CallTimeout(),
		Variables: model.UnionStringMaps(
			attempt.resource.Variables(),
			queue.Variables(),
			attempt.Variables(),
			map[string]string{
				model.CALL_TIMEOUT_VARIABLE:            fmt.Sprintf("%d", queue.Timeout()),
				model.CALL_IGNORE_EARLY_MEDIA_VARIABLE: "true",
				"ignore_display_updates":               "true",
				"hangup_after_bridge":                  "true",
				"absolute_codec_string":                "PCMA",
				"sip_h_X-Webitel-Direction":            "internal",
				//"sip_h_X-Webitel-Direction":   "inbound",
				"sip_route_uri":               queue.SipRouterAddr(),
				model.CALL_DIRECTION_VARIABLE: model.CALL_DIRECTION_DIALER,
				model.CALL_DOMAIN_VARIABLE:    queue.Domain(),
				model.QUEUE_ID_FIELD:          fmt.Sprintf("%d", queue.id),
				model.QUEUE_NAME_FIELD:        queue.name,
				model.QUEUE_TYPE_NAME_FIELD:   queue.TypeName(),
				model.QUEUE_SIDE_FIELD:        model.QUEUE_SIDE_AGENT,
				model.QUEUE_MEMBER_ID_FIELD:   fmt.Sprintf("%d", attempt.MemberId()),
				model.QUEUE_ATTEMPT_ID_FIELD:  fmt.Sprintf("%d", attempt.Id()),
				model.QUEUE_RESOURCE_ID_FIELD: fmt.Sprintf("%d", attempt.resource.Id()),
			},
		),
		Applications: make([]*model.CallRequestApplication, 0, 4),
	}

	callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
		AppName: "bridge",
		//Args:    info.LegBUri,
		//Args: "{sip_h_X-Webitel-Direction=internal,sip_route_uri=sip:192.168.177.11}sofia/sip/9999@webitel.lo",
		Args: "sofia/sip/member@10.10.10.200:5080",
	})

	call := queue.NewCallUseResource(callRequest, attempt.resource)
	call.Invite()

	var calling = true

	for calling {
		select {
		case state := <-call.State():
			switch state {
			case call_manager.CALL_STATE_ACCEPT:
				queue.queueManager.agentManager.SetAgentState(agent, model.AGENT_STATE_RINGING, 0)
			case call_manager.CALL_STATE_BRIDGE:
				queue.queueManager.agentManager.SetAgentState(agent, model.AGENT_STATE_TALK, 0)
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
