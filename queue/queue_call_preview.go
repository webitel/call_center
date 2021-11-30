package queue

import (
	"encoding/json"
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
	Recordings bool `json:"recordings"`
	RecordMono bool `json:"record_mono"`
	RecordAll  bool `json:"record_all"`

	OriginateTimeout       uint16 `json:"originate_timeout"`
	WaitBetweenRetries     uint64 `json:"wait_between_retries"`
	MaxAttempts            uint   `json:"max_attempts"`
	WaitBetweenRetriesDesc bool   `json:"wait_between_retries_desc"`
	AllowGreetingAgent     bool   `json:"allow_greeting_agent"`
}

func PreviewSettingsFromBytes(data []byte) PreviewSettings {
	var settings PreviewSettings
	json.Unmarshal(data, &settings)
	return settings
}

func NewPreviewCallQueue(callQueue CallingQueue, settings PreviewSettings) QueueObject {
	return &PreviewCallQueue{
		CallingQueue:    callQueue,
		PreviewSettings: settings,
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

	attempt.waitBetween = queue.WaitBetweenRetries
	attempt.maxAttempts = queue.MaxAttempts

	go queue.run(team, attempt, attempt.Agent())

	return nil
}

func (queue *PreviewCallQueue) run(team *agentTeam, attempt *Attempt, agent agent_manager.AgentObject) {

	if !queue.queueManager.DoDistributeSchema(&queue.BaseQueue, attempt) {
		queue.queueManager.LeavingMember(attempt)
		return
	}

	// joined

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
				//"absolute_codec_string":      "opus,pcmu,pcma",
				"cc_reporting": fmt.Sprintf("%v", queue.Processing()),

				"hangup_after_bridge": "true",
				"continue_on_fail":    "true",

				"sip_h_X-Webitel-Display-Direction": "outbound",
				"sip_h_X-Webitel-Origin":            "request",
				"wbt_destination":                   attempt.Destination(),
				"wbt_from_id":                       fmt.Sprintf("%v", agent.Id()),
				"wbt_from_number":                   agent.CallNumber(),
				"wbt_from_name":                     agent.Name(),
				"wbt_from_type":                     "user", //todo agent ?

				"wbt_to_id":     fmt.Sprintf("%d", *attempt.MemberId()),
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
				model.QUEUE_MEMBER_ID_FIELD:   fmt.Sprintf("%d", *attempt.MemberId()),
				model.QUEUE_ATTEMPT_ID_FIELD:  fmt.Sprintf("%d", attempt.Id()),
				model.QUEUE_RESOURCE_ID_FIELD: fmt.Sprintf("%d", attempt.resource.Id()),
			},
		),
		Applications: make([]*model.CallRequestApplication, 0, 3),
	}

	call, err := queue.NewCall(callRequest)
	if err != nil {
		attempt.Log(err.Error())
		// TODO
		queue.queueManager.SetAttemptAbandonedWithParams(attempt, queue.MaxAttempts, queue.WaitBetweenRetries, nil)
		queue.queueManager.LeavingMember(attempt)
		return
	}

	attempt.memberChannel = call

	if queue.Recordings {
		queue.SetRecordings(call, queue.RecordAll, queue.RecordMono)
	}

	callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
		AppName: "bridge",
		Args:    attempt.resource.Gateway().Bridge(attempt.MemberCallId(), call.Id(), attempt.Name(), attempt.Destination(), display, queue.OriginateTimeout),
	})

	callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
		AppName: "playback",
		Args:    "tone_stream://L=3;%(400,400,425)",
	})

	team.Distribute(queue, agent, NewDistributeEvent(attempt, agent.UserId(), queue, agent, queue.Processing(), nil, call))
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
				if queue.AllowGreetingAgent {
					call.BroadcastPlaybackFile(agent.DomainId(), agent.GreetingMedia(), "both")
				}
			}
		case <-call.HangupChan():
			if call.TransferTo() != nil && call.TransferToAgentId() != nil && call.TransferFromAttemptId() != nil {
				attempt.Log("receive transfer")
				if nc, err := queue.GetTransferredCall(*call.TransferTo()); err != nil {
					wlog.Error(err.Error())
				} else {
					if nc.HangupAt() == 0 {
						if newA, err := queue.queueManager.TransferFrom(team, attempt, *call.TransferFromAttemptId(), *call.TransferToAgentId(), *call.TransferTo(), nc); err == nil {
							agent = newA
							attempt.Log(fmt.Sprintf("transfer call from [%s] to [%s] AGENT_ID = %s {%d, %d}", call.Id(), nc.Id(), newA.Name(), attempt.Id(), *call.TransferFromAttemptId()))
						} else {
							wlog.Error(err.Error())
						}

						call = nc
						continue
					}
				}
			}
			calling = false
		}
	}

	if call.AcceptAt() > 0 || attempt.Callback() != nil {
		team.Reporting(queue, attempt, agent, call.ReportingAt() > 0, call.Transferred())
	} else {
		team.CancelAgentAttempt(attempt, agent)
		queue.queueManager.LeavingMember(attempt)
	}
}

func printfIfErr(err *model.AppError) {
	if err != nil {
		wlog.Error(err.Error())
	}
}
