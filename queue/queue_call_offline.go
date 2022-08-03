package queue

import (
	"encoding/json"
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
)

type OfflineQueueSettings struct {
	Recordings bool `json:"recordings"`
	RecordMono bool `json:"record_mono"`
	RecordAll  bool `json:"record_all"`

	OriginateTimeout   uint16 `json:"originate_timeout"`
	WaitBetweenRetries uint64 `json:"wait_between_retries"`
	MaxAttempts        uint   `json:"max_attempts"`
	PerNumbers         bool   `json:"per_numbers"`
}

type OfflineCallQueue struct {
	CallingQueue
	OfflineQueueSettings
}

func QueueOfflineSettingsFromBytes(data []byte) OfflineQueueSettings {
	var settings OfflineQueueSettings
	json.Unmarshal(data, &settings)
	return settings
}

func NewOfflineCallQueue(callQueue CallingQueue, settings OfflineQueueSettings) QueueObject {
	return &OfflineCallQueue{
		CallingQueue:         callQueue,
		OfflineQueueSettings: settings,
	}
}

func (queue *OfflineCallQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
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
	attempt.perNumbers = queue.PerNumbers

	go queue.run(team, attempt, attempt.agent)
	return nil
}

func (queue *OfflineCallQueue) run(team *agentTeam, attempt *Attempt, agent agent_manager.AgentObject) {

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

				"hangup_after_bridge": "true",
				"bridge_early_media":  "true",
				//"absolute_codec_string": "opus,pcmu,pcma",
				"cc_reporting": fmt.Sprintf("%v", queue.Processing()),

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

				model.QUEUE_ID_FIELD:        fmt.Sprintf("%d", queue.Id()),
				model.QUEUE_NAME_FIELD:      queue.Name(),
				model.QUEUE_TYPE_NAME_FIELD: queue.TypeName(),

				model.QUEUE_MEMBER_ID_FIELD:   fmt.Sprintf("%d", *attempt.MemberId()),
				model.QUEUE_ATTEMPT_ID_FIELD:  fmt.Sprintf("%d", attempt.Id()),
				model.QUEUE_RESOURCE_ID_FIELD: fmt.Sprintf("%d", attempt.resource.Id()),
			},
		),
		Applications: make([]*model.CallRequestApplication, 0, 1),
	}

	call, err := queue.NewCall(callRequest)
	if err != nil {
		attempt.Log(err.Error())
		// TODO
		queue.queueManager.SetAttemptAbandonedWithParams(attempt, queue.MaxAttempts, queue.WaitBetweenRetries, nil)
		queue.queueManager.LeavingMember(attempt)
		return
	}

	queue.SetHoldMusic(callRequest)

	callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
		AppName: "bridge",
		Args: attempt.resource.Gateway().Bridge(model.BridgeRequest{
			Id:          attempt.MemberCallId(),
			ParentId:    call.Id(),
			Name:        attempt.Name(),
			Destination: attempt.Destination(),
			Display:     attempt.Display(),
			Timeout:     queue.OriginateTimeout,
			Recordings:  queue.Recordings,
			RecordMono:  queue.RecordMono,
			RecordAll:   queue.RecordAll,
		}),
	})

	team.Distribute(queue, agent, NewDistributeEvent(attempt, agent.UserId(), queue, agent, queue.Processing(), nil, call))
	call.Invite()

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

	if call.BillSeconds() > 0 || call.AcceptAt() > 0 { //FIXME Accept or Bridge ?
		wlog.Debug(fmt.Sprintf("attempt[%d] reporting...", attempt.Id()))
		team.Reporting(queue, attempt, agent, call.ReportingAt() > 0, call.Transferred())
	} else {
		team.Missed(attempt, agent)
	}
}
