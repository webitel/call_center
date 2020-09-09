package queue

import (
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
)

func (queue *CallingQueue) AgentCallRequest(agent agent_manager.AgentObject, at *agentTeam, attempt *Attempt, apps []*model.CallRequestApplication) *model.CallRequest {
	cr := &model.CallRequest{
		Endpoints:   agent.GetCallEndpoints(),
		Strategy:    model.CALL_STRATEGY_DEFAULT,
		Destination: attempt.Destination(),
		Variables: model.UnionStringMaps(
			queue.Variables(),
			attempt.ExportVariables(),
			map[string]string{
				//"ignore_early_media": "true",
				"absolute_codec_string":     "opus,pcmu,pcma",
				"hangup_after_bridge":       "true",
				"ignore_display_updates":    "true",
				"cc_reporting":              fmt.Sprintf("%v", at.PostProcessing()),
				model.CallVariableDomainId:  fmt.Sprintf("%v", queue.DomainId()),
				model.CallVariableUserId:    fmt.Sprintf("%v", agent.UserId()),
				"bridge_export_vars":        "cc_agent_id",
				"sip_h_X-Webitel-Direction": "internal",
				"wbt_destination":           attempt.Destination(),
				"wbt_to_id":                 fmt.Sprintf("%v", agent.Id()),
				"wbt_to_number":             agent.CallNumber(),
				"wbt_to_name":               agent.Name(),
				"wbt_to_type":               "user", //todo agent ?

				"wbt_from_name":   attempt.Name(),
				"wbt_from_type":   "member",
				"wbt_from_number": attempt.Destination(),

				"effective_caller_id_name":   attempt.Name(),
				"effective_caller_id_number": attempt.Destination(),

				"origination_callee_id_name":   agent.Name(),
				"origination_callee_id_number": agent.CallNumber(),
				"origination_caller_id_name":   attempt.Name(),
				"origination_caller_id_number": attempt.Destination(),

				model.QUEUE_AGENT_ID_FIELD:   fmt.Sprintf("%d", agent.Id()),
				model.QUEUE_TEAM_ID_FIELD:    fmt.Sprintf("%d", at.Id()),
				model.QUEUE_ID_FIELD:         fmt.Sprintf("%d", queue.Id()),
				model.QUEUE_NAME_FIELD:       queue.Name(),
				model.QUEUE_TYPE_NAME_FIELD:  queue.TypeName(),
				model.QUEUE_ATTEMPT_ID_FIELD: fmt.Sprintf("%d", attempt.Id()),
			},
		),
		Timeout:      at.CallTimeout(),
		CallerName:   attempt.Name(),
		CallerNumber: attempt.Destination(),
	}

	if attempt.MemberId() != nil {
		cr.Variables["wbt_from_id"] = fmt.Sprintf("%d", *attempt.MemberId())
		cr.Variables[model.QUEUE_MEMBER_ID_FIELD] = cr.Variables["wbt_from_id"]
	}

	if agent.GreetingMedia() != nil {
		cr.Applications = append([]*model.CallRequestApplication{
			{
				AppName: "playback",
				Args:    model.RingtoneUri(agent.DomainId(), agent.GreetingMedia().Id, agent.GreetingMedia().Type),
			},
		}, apps...)
	} else {
		cr.Applications = apps
	}

	return cr
}

func (queue *CallingQueue) MissedAgentAttempt(attemptId int64, agentId int, call call_manager.Call) *model.AppError {
	missed := &model.MissedAgentAttempt{
		AttemptId: attemptId,
		AgentId:   agentId,
		Cause:     call.HangupCause(),
		MissedAt:  call.HangupAt(),
	}

	return queue.queueManager.store.Agent().CreateMissed(missed)
}
