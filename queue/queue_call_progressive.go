package queue

import (
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
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
	if attempt.resource == nil {
		return NewErrorResourceRequired(queue, attempt)
	}

	if attempt.agent == nil {
		return NewErrorAgentRequired(queue, attempt)
	}

	go queue.run(attempt, attempt.Agent())

	return nil
}

type progressiveQueueContext struct {
	attempt   *Attempt
	call      call_manager.Call
	agentCall call_manager.Call
	agent     agent_manager.AgentObject
	team      *agentTeam
}

func (queue *ProgressiveCallQueue) reporting(attempt *Attempt, call, agentCall call_manager.Call, agent agent_manager.AgentObject, team *agentTeam) {
	attempt.SetState(model.MEMBER_STATE_POST_PROCESS)
	wlog.Debug(fmt.Sprintf("attempt[%d] start reporting", attempt.Id()))

	result := &model.AttemptResult{}
	result.Id = attempt.Id()
	if call != nil {
		result.LegAId = model.NewString(call.Id())
		result.OfferingAt = call.OfferingAt()
		result.AnsweredAt = call.AcceptAt()

		if call.BillSeconds() > 0 {
			result.Result = model.MEMBER_CAUSE_SUCCESSFUL
			result.BridgedAt = call.BridgeAt()
		} else {
			result.Result = model.MEMBER_CAUSE_ABANDONED
		}
		result.HangupAt = call.HangupAt()
	} else {
		result.HangupAt = model.GetMillis()
	}

	if agentCall != nil && agent != nil && team != nil {
		result.AgentId = model.NewInt(agent.Id())
		err := team.ReportingCall(&queue.CallingQueue, agent, agentCall, attempt)
		if err != nil {
			wlog.Error(err.Error())
		}
	}
	result.State = model.MEMBER_STATE_END

	attempt.SetResult(model.NewString(result.Result))

	//if err := queue.SetAttemptResult(result); err != nil {
	//	wlog.Error(fmt.Sprintf("attempt [%d] set result error: %s", attempt.Id(), err.Error()))
	//}

	close(attempt.distributeAgent)
	close(attempt.done)
	wlog.Debug(fmt.Sprintf("attempt[%d] reporting: %v", attempt.Id(), result))
	queue.queueManager.LeavingMember(attempt, queue)
}

func (queue *ProgressiveCallQueue) run(attempt *Attempt, agent agent_manager.AgentObject) {
	var err *model.AppError

	var ctx = &progressiveQueueContext{
		attempt: attempt,
	}

	defer func(c *progressiveQueueContext) {
		queue.reporting(c.attempt, c.call, c.agentCall, c.agent, c.team)
	}(ctx)

	ctx.team, err = queue.GetTeam(attempt)
	if err != nil {
		//FIXME
		panic(err.Error())
	}

	dst := attempt.resource.Gateway().Endpoint(attempt.Destination())
	var callerIdNumber string

	if attempt.destination.Display != nil && *attempt.destination.Display != "" {
		callerIdNumber = *attempt.destination.Display
	} else {
		callerIdNumber = attempt.resource.GetDisplay()
	}

	callRequest := &model.CallRequest{
		Endpoints:    []string{dst},
		CallerNumber: attempt.Destination(),
		CallerName:   attempt.Name(),
		Timeout:      queue.Timeout(),
		Destination:  attempt.Destination(),
		Variables: model.UnionStringMaps(
			queue.Variables(),
			attempt.ExportVariables(),
			map[string]string{
				model.CallVariableDomainName:  queue.Domain(),
				model.CallVariableDomainId:    fmt.Sprintf("%v", queue.DomainId()),
				model.CallVariableGatewayId:   fmt.Sprintf("%v", attempt.resource.Gateway().Id),
				model.CallVariableGatewayName: fmt.Sprintf("%v", attempt.resource.Gateway().Name),

				"hangup_after_bridge": "true",

				"sip_h_X-Webitel-Display-Direction": "outbound",
				"sip_h_X-Webitel-Origin":            "request",
				"wbt_destination":                   attempt.Destination(),
				"wbt_from_id":                       fmt.Sprintf("%v", attempt.resource.Gateway().Id), //FIXME gateway id ?
				"wbt_from_number":                   callerIdNumber,
				"wbt_from_name":                     attempt.resource.Gateway().Name,
				"wbt_from_type":                     "gateway",

				"wbt_to_id":     fmt.Sprintf("%v", attempt.MemberId()),
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
				model.QUEUE_MEMBER_ID_FIELD:   fmt.Sprintf("%d", attempt.MemberId()),
				model.QUEUE_ATTEMPT_ID_FIELD:  fmt.Sprintf("%d", attempt.Id()),
				model.QUEUE_RESOURCE_ID_FIELD: fmt.Sprintf("%d", attempt.resource.Id()),
			},
		),
		Applications: []*model.CallRequestApplication{
			{
				AppName: "park",
			},
		},
	}
	//todo fire event

	ctx.call = queue.NewCallUseResource(callRequest, attempt.resource)
	ctx.call.Invite()
	if ctx.call.Err() != nil {
		return
	}

	ctx.agent = attempt.Agent()

	var calling = true

	for calling {
		select {
		case state := <-ctx.call.State():
			switch state {
			case call_manager.CALL_STATE_ACCEPT:
				if cnt, err := queue.queueManager.store.Agent().ConfirmAttempt(agent.Id(), attempt.Id()); err != nil {
					ctx.call.Hangup(model.CALL_HANGUP_NORMAL_UNSPECIFIED) // TODO
				} else if cnt > 0 {
					cr := queue.AgentCallRequest(ctx.agent, ctx.team, attempt)
					cr.Applications = []*model.CallRequestApplication{
						{
							AppName: "set",
							Args:    fmt.Sprintf("bridge_export_vars=%s,%s", model.QUEUE_AGENT_ID_FIELD, model.QUEUE_TEAM_ID_FIELD),
						},
						{
							AppName: "park",
						},
					}
					cr.Variables["wbt_parent_id"] = ctx.call.Id()

					if err = ctx.team.OfferingCall(queue, ctx.agent, attempt); err != nil {
						wlog.Error(err.Error())
					}
					ctx.agentCall = ctx.call.NewCall(cr)
					ctx.agentCall.Invite()

					wlog.Debug(fmt.Sprintf("call [%s] && agent [%s]", ctx.call.Id(), ctx.agentCall.Id()))

				top:
					for ctx.agentCall.HangupCause() == "" && ctx.call.HangupCause() == "" {
						select {
						case state := <-ctx.agentCall.State():
							attempt.Log(fmt.Sprintf("agent call state %d", state))
							switch state {
							case call_manager.CALL_STATE_ACCEPT:
								ctx.agentCall.Bridge(ctx.call)
								ctx.team.Talking(queue, ctx.agent, attempt)

							case call_manager.CALL_STATE_HANGUP:
								if ctx.call.HangupAt() == 0 {
									ctx.call.Hangup("")
									ctx.call.WaitForHangup()
								}
								break top
							}
						case <-ctx.call.HangupChan():
							attempt.Log(fmt.Sprintf("call hangup %s", ctx.call.Id()))
							if ctx.agentCall.HangupAt() == 0 {
								if ctx.call.BridgeAt() > 0 {
									ctx.agentCall.Hangup(model.CALL_HANGUP_NORMAL_CLEARING)
								} else {
									ctx.agentCall.Hangup(model.CALL_HANGUP_ORIGINATOR_CANCEL)
								}
							}

							ctx.agentCall.WaitForHangup()
							attempt.Log(fmt.Sprintf("[%s] call %s receive hangup", ctx.agentCall.NodeName(), ctx.agentCall.Id()))
							break top
						}
					}
				}
			}
		case result := <-attempt.cancel:
			switch result {
			case model.MEMBER_CAUSE_CANCEL:
				ctx.call.Hangup(model.CALL_HANGUP_LOSE_RACE)
			}
		case <-ctx.call.HangupChan():
			calling = false
		}

	}
}
