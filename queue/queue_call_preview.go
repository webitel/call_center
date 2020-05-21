package queue

import (
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
)

// FIXME AgentQueue
type PreviewCallQueue struct {
	CallingQueue
	PreviewSettings
}

type PreviewSettings struct {
	DoCallFlowId       *int `json:"do_call_flow_id"`
	MemberCallTimeout  int  `json:"member_call_timeout"`
	WaitBetweenRetries int  `json:"wait_between_retries"`
}

func NewPreviewCallQueue(callQueue CallingQueue) QueueObject {
	return &PreviewCallQueue{
		CallingQueue: callQueue,
	}
}

func (queue *PreviewCallQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	if attempt.resource == nil {
		return NewErrorResourceRequired(queue, attempt)
	}

	if attempt.agent == nil {
		return NewErrorAgentRequired(queue, attempt)
	}

	team, err := queue.GetTeam(attempt)
	if err != nil {
		return err
	}

	go queue.run(team, attempt, attempt.Agent(), attempt.Destination())

	return nil
}

func (queue *PreviewCallQueue) run(team *agentTeam, attempt *Attempt, agent agent_manager.AgentObject, destination string) {

	display := attempt.Display()

	callRequest := &model.CallRequest{
		Endpoints:    agent.GetCallEndpoints(),
		CallerName:   attempt.Name(),
		CallerNumber: attempt.Destination(),
		Timeout:      team.CallTimeout(),
		Variables: model.UnionStringMaps(
			queue.Variables(),
			attempt.ExportVariables(),
			map[string]string{
				model.CallVariableDomainName: queue.Domain(),
				model.CallVariableDomainId:   fmt.Sprintf("%v", queue.DomainId()),
				model.CallVariableUserId:     fmt.Sprintf("%v", agent.UserId()),
				model.CallVariableDirection:  "internal",

				"cc_reporting": fmt.Sprintf("%v", team.PostProcessing()),

				"hangup_after_bridge": "true",

				"sip_h_X-Webitel-Display-Direction": "outbound",
				"sip_h_X-Webitel-Origin":            "request",
				"wbt_destination":                   attempt.Destination(),
				"wbt_from_id":                       fmt.Sprintf("%v", agent.Id()),
				"wbt_from_number":                   agent.CallNumber(),
				"wbt_from_name":                     agent.Name(),
				"wbt_from_type":                     "user", //todo agent ?

				"wbt_to_id":     fmt.Sprintf("%d", attempt.MemberId()),
				"wbt_to_name":   attempt.Name(),
				"wbt_to_type":   "member",
				"wbt_to_number": attempt.Destination(),

				"effective_caller_id_number": agent.CallNumber(),
				"effective_caller_id_name":   agent.Name(),

				"effective_callee_id_name":   attempt.Name(),
				"effective_callee_id_number": attempt.Destination(),

				"origination_caller_id_name":   attempt.Name(),
				"origination_caller_id_number": attempt.Destination(),
				"origination_callee_id_name":   agent.Name(),
				"origination_callee_id_number": agent.CallNumber(),

				model.QUEUE_AGENT_ID_FIELD:    fmt.Sprintf("%d", agent.Id()),
				model.QUEUE_TEAM_ID_FIELD:     fmt.Sprintf("%d", team.Id()),
				model.QUEUE_ID_FIELD:          fmt.Sprintf("%d", queue.Id()),
				model.QUEUE_NAME_FIELD:        queue.Name(),
				model.QUEUE_TYPE_NAME_FIELD:   queue.TypeName(),
				model.QUEUE_MEMBER_ID_FIELD:   fmt.Sprintf("%d", attempt.MemberId()),
				model.QUEUE_ATTEMPT_ID_FIELD:  fmt.Sprintf("%d", attempt.Id()),
				model.QUEUE_RESOURCE_ID_FIELD: fmt.Sprintf("%d", attempt.resource.Id()),
			},
		),
		Applications: make([]*model.CallRequestApplication, 0, 1),
	}

	call := queue.NewCall(callRequest)

	callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
		AppName: "bridge",
		Args:    attempt.resource.Gateway().Bridge(call.Id(), attempt.Destination(), display),
	})

	queue.Hook(model.NewInt(agent.Id()), NewDistributeEvent(attempt, queue, agent, nil, call))

	printfIfErr(call.Invite())
	var calling = true

	for calling {
		select {
		case state := <-call.State():
			switch state {
			case call_manager.CALL_STATE_RINGING:
				team.Offering(attempt, agent, call, nil)
			case call_manager.CALL_STATE_ACCEPT:
				team.Answered(attempt, agent)
			case call_manager.CALL_STATE_BRIDGE:
				team.Bridged(attempt, agent)
			}
		case <-call.HangupChan():
			calling = false
		}
	}

	if call.AnswerSeconds() > 0 { //FIXME Accept or Bridge ?

		// FIXME
		if team.PostProcessing() && call.ReportingAt() > 0 {
			team.WrapTime(attempt, agent, call.ReportingAt())
		} else {
			wlog.Debug(fmt.Sprintf("attempt[%d] reporting...", attempt.Id()))
			team.Reporting(attempt, agent)
		}
	} else {
		team.Missed(attempt, queue.WaitBetweenRetries, agent)
	}

	close(attempt.distributeAgent)
	queue.queueManager.LeavingMember(attempt, queue)
}

func printfIfErr(err *model.AppError) {
	if err != nil {
		panic(err.Error())
	}
}
