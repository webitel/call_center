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
}

func NewPreviewCallQueue(callQueue CallingQueue) QueueObject {
	return &PreviewCallQueue{
		CallingQueue: callQueue,
	}
}

func (preview *PreviewCallQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	if attempt.resource == nil {
		return NewErrorResourceRequired(preview, attempt)
	}

	if attempt.agent == nil {
		return NewErrorAgentRequired(preview, attempt)
	}

	team, err := preview.GetTeam(attempt)
	if err != nil {
		return err
	}

	go preview.run(team, attempt, attempt.Agent(), attempt.Destination())

	return nil
}

func (queue *PreviewCallQueue) reporting(attempt *Attempt) {
	attempt.SetState(model.MEMBER_STATE_POST_PROCESS)

	info := queue.GetCallInfoFromAttempt(attempt)
	wlog.Debug(fmt.Sprintf("attempt[%d] start reporting", attempt.Id()))
	result := &model.AttemptResult{}
	result.Id = attempt.Id()
	if info.fromCall != nil {
		result.LegAId = model.NewString(info.fromCall.Id())

		if info.agent != nil {
			result.AgentId = model.NewInt(info.agent.Id())
			result.LegBId = model.NewString(info.toCall.Id())

			team, err := queue.GetTeam(attempt)
			if err != nil {
				//FIXME
			}
			team.ReportingCall(&queue.CallingQueue, info.agent, info.toCall, attempt)
		}

		result.OfferingAt = info.fromCall.OfferingAt()
		result.AnsweredAt = info.fromCall.AcceptAt()

		if info.fromCall.BillSeconds() > 0 {
			result.Result = model.MEMBER_CAUSE_SUCCESSFUL
			result.BridgedAt = info.fromCall.BridgeAt()
		} else {
			result.Result = model.MEMBER_CAUSE_ABANDONED
		}
		result.HangupAt = info.fromCall.HangupAt()
	} else {
		attempt.Agent().SetStateReporting(5) //FIXME
		result.HangupAt = model.GetMillis()
	}
	result.State = model.MEMBER_STATE_END

	//attempt.SetResult(model.NewString(result.Result))

	if err := queue.SetAttemptResult(result); err != nil {
		wlog.Error(fmt.Sprintf("attempt [%d] set result error: %s", attempt.Id(), err.Error()))
	}
	close(attempt.distributeAgent)
	wlog.Debug(fmt.Sprintf("attempt[%d] reporting: %v", attempt.Id(), result))
	queue.queueManager.LeavingMember(attempt, queue)
}

func (queue *PreviewCallQueue) run(team *agentTeam, attempt *Attempt, agent agent_manager.AgentObject, destination string) {

	defer queue.reporting(attempt)

	callRequest := &model.CallRequest{
		Endpoints:    agent.GetCallEndpoints(),
		CallerName:   attempt.Name(),
		CallerNumber: attempt.Destination(),
		Timeout:      team.CallTimeout(),
		Variables: model.UnionStringMaps(
			queue.Variables(),
			attempt.Variables(),
			map[string]string{
				model.CALL_DOMAIN_VARIABLE:  queue.Domain(),
				model.CallVariableDomainId:  fmt.Sprintf("%v", queue.DomainId()),
				model.CallVariableUserId:    fmt.Sprintf("%v", agent.UserId()),
				model.CallVariableDirection: "internal",

				"hangup_after_bridge": "true",

				"sip_h_X-Webitel-Display-Direction": "outbound",
				"sip_h_X-Webitel-Origin":            "request",
				"wbt_destination":                   attempt.Destination(),
				"wbt_from_id":                       fmt.Sprintf("%v", agent.Id()),
				"wbt_from_number":                   agent.CallNumber(),
				"wbt_from_name":                     agent.Name(),
				"wbt_from_type":                     "user", //todo agent ?

				"wbt_to_id":     fmt.Sprintf("%v", attempt.MemberId()),
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

				model.QUEUE_ID_FIELD:        fmt.Sprintf("%d", queue.Id()),
				model.QUEUE_NAME_FIELD:      queue.Name(),
				model.QUEUE_TYPE_NAME_FIELD: queue.TypeName(),

				model.QUEUE_SIDE_FIELD:        model.QUEUE_SIDE_MEMBER,
				model.QUEUE_MEMBER_ID_FIELD:   fmt.Sprintf("%d", attempt.MemberId()),
				model.QUEUE_ATTEMPT_ID_FIELD:  fmt.Sprintf("%d", attempt.Id()),
				model.QUEUE_RESOURCE_ID_FIELD: fmt.Sprintf("%d", attempt.resource.Id()),
			},
		),
		Applications: make([]*model.CallRequestApplication, 0, 1),
	}

	callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
		AppName: "sleep",
		Args:    "10000",
	})

	call := queue.NewCall(callRequest)
	call.Invite()

	var calling = true
	agent.SetStateOffering(queue.id)
	for calling {
		select {
		case state := <-call.State():
			switch state {
			case call_manager.CALL_STATE_ACCEPT:

			case call_manager.CALL_STATE_BRIDGE:
				agent.SetStateTalking()
			}
		case <-call.HangupChan():
			calling = false
		}
	}
}
