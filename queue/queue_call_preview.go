package queue

import (
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
	"strings"
)

type PreviewCallQueue struct {
	CallingQueue
}

func NewPreviewCallQueue(callQueue CallingQueue) QueueObject {
	return &PreviewCallQueue{
		CallingQueue: callQueue,
	}
}

func (preview *PreviewCallQueue) DistributeAttempt(attempt *Attempt) {
	Assert(attempt.resource)
	Assert(attempt.agent)

	attempt.Info = &AttemptInfoCall{}

	go preview.makeCallToAgent(attempt, attempt.Agent())
}

func (preview *PreviewCallQueue) makeCallToAgent(attempt *Attempt, agent agent_manager.AgentObject) {

	info := preview.GetCallInfoFromAttempt(attempt)

	if attempt.GetCommunicationPattern() == nil {
		panic(123) //TODO
	}
	endpoint, e := preview.resourceManager.GetEndpoint(*attempt.GetCommunicationPattern())
	if e != nil {
		panic(e.Error()) //TODO
	}

	info.LegBUri = endpoint.Parse(attempt.resource.GetDialString(), attempt.Destination())
	info.LegAUri = strings.Join(agent.GetCallEndpoints(), ",")

	team, _ := preview.GetTeam(attempt)
	fmt.Println(team.CallTimeout())

	callRequest := &model.CallRequest{
		Endpoints:    []string{"sofia/sip/agent@10.10.10.200:5080"}, //agent.GetCallEndpoints(), //agent.GetCallEndpoints(), // []string{"null"},
		CallerName:   attempt.Name(),
		CallerNumber: attempt.Destination(),
		Timeout:      60,
		Variables: model.UnionStringMaps(
			attempt.resource.Variables(),
			preview.Variables(),
			attempt.Variables(),
			map[string]string{
				model.CALL_TIMEOUT_VARIABLE:            fmt.Sprintf("%d", preview.Timeout()),
				model.CALL_IGNORE_EARLY_MEDIA_VARIABLE: "true",
				"ignore_display_updates":               "true",
				"hangup_after_bridge":                  "true",
				"absolute_codec_string":                "PCMA",
				//"sip_h_X-Webitel-Direction":            "internal",
				//"sip_h_X-Webitel-Direction":   "inbound",
				//"sip_route_uri":               preview.SipRouterAddr(),
				model.CALL_DIRECTION_VARIABLE: model.CALL_DIRECTION_DIALER,
				model.CALL_DOMAIN_VARIABLE:    preview.Domain(),
				model.QUEUE_ID_FIELD:          fmt.Sprintf("%d", preview.id),
				model.QUEUE_NAME_FIELD:        preview.name,
				model.QUEUE_TYPE_NAME_FIELD:   preview.TypeName(),
				model.QUEUE_SIDE_FIELD:        model.QUEUE_SIDE_AGENT,
				model.QUEUE_MEMBER_ID_FIELD:   fmt.Sprintf("%d", attempt.MemberId()),
				model.QUEUE_ATTEMPT_ID_FIELD:  fmt.Sprintf("%d", attempt.Id()),
				model.QUEUE_RESOURCE_ID_FIELD: fmt.Sprintf("%d", attempt.resource.Id()),
				model.QUEUE_ROUTING_ID_FIELD:  fmt.Sprintf("%d", attempt.CommunicationRoutingId()),
			},
		),
		Applications: make([]*model.CallRequestApplication, 0, 4),
	}

	if preview.RecordCallEnabled() {
		preview.SetRecordCall(callRequest, model.CALL_RECORD_SESSION_TEMPLATE)
		info.UseRecordings = true
	}

	callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
		AppName: "bridge",
		//Args:    info.LegBUri,
		//Args: "{sip_h_X-Webitel-Direction=internal,sip_route_uri=sip:192.168.177.11}sofia/sip/9999@webitel.lo",
		Args: "sofia/sip/member@10.10.10.200:5080",
	})

	preview.queueManager.agentManager.SetAgentState(agent, model.AGENT_STATE_OFFERING, 0)
	call := preview.NewCallUseResource(callRequest, attempt.CommunicationRoutingId(), attempt.resource)

	defer preview.queueManager.AgentReportingCall(team, agent, call)

	if call.Err() != nil {
		preview.CallError(attempt, call.Err(), call.HangupCause())
		preview.queueManager.LeavingMember(attempt, preview)
		return
	}

	wlog.Debug(fmt.Sprintf("create call %s for member %s attemptId %v", call.Id(), attempt.Name(), attempt.Id()))

	call.Invite()

	var calling = true

	for calling {
		select {
		case state := <-call.State():
			switch state {
			case call_manager.CALL_STATE_ACCEPT:
				preview.queueManager.agentManager.SetAgentState(agent, model.AGENT_STATE_RINGING, 0)
			case call_manager.CALL_STATE_BRIDGE:
				preview.queueManager.agentManager.SetAgentState(agent, model.AGENT_STATE_TALK, 0)
			}
		case <-call.HangupChan():
			calling = false
		}
	}

	call.WaitForHangup()

	if call.HangupCause() == "" {
		preview.StopAttemptWithCallDuration(attempt, model.MEMBER_CAUSE_SUCCESSFUL, 0) //TODO
	} else {
		preview.StopAttemptWithCallDuration(attempt, call.HangupCause(), 0) //TODO
	}

	preview.queueManager.LeavingMember(attempt, preview)
}
