package queue

import (
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
)

type CallingQueueObject interface {
}

type CallingQueue struct {
	BaseQueue
	params model.QueueDialingSettings
}

func (queue *CallingQueue) CallContextName() string {
	return "call_center"
}

func (queue *CallingQueue) FlowEndpoints() []string {
	return []string{"null"}
}

func (queue *CallingQueue) RecordCallEnabled() bool {
	return queue.params.Recordings
}

func (queue *CallingQueue) SetAmdCall(callRequest *model.CallRequest, amd *model.QueueAmdSettings, onHuman, onMachine, onNotSure string) {
	callRequest.Variables[model.CALL_AMD_HUMAN_VARIABLE] = onHuman
	callRequest.Variables[model.CALL_AMD_MACHINE_VARIABLE] = onMachine
	callRequest.Variables[model.CALL_AMD_NOT_SURE_VARIABLE] = onNotSure

	callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
		AppName: model.CALL_AMD_APPLICATION_NAME,
		Args:    amd.ToArgs(),
	})

	if amd.PlaybackFileUri != "" {
		if amd.PlaybackFileSilenceTime > 0 {
			callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
				AppName: model.CALL_SLEEP_APPLICATION,
				Args:    fmt.Sprintf("%d", amd.PlaybackFileSilenceTime),
			})
		}

		callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
			AppName: model.CALL_PLAYBACK_APPLICATION,
			Args:    amd.PlaybackFileUri,
		})

		if amd.TotalAnalysisTime-amd.PlaybackFileSilenceTime > 0 {
			callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
				AppName: model.CALL_SLEEP_APPLICATION,
				Args:    fmt.Sprintf("%d", amd.TotalAnalysisTime-amd.PlaybackFileSilenceTime+100), // TODO 100 ?
			})
		}
	} else {
		callRequest.Applications = append(callRequest.Applications, &model.CallRequestApplication{
			AppName: model.CALL_SLEEP_APPLICATION,
			Args:    fmt.Sprintf("%d", amd.TotalAnalysisTime+100),
		})
	}
}

func (queue *CallingQueue) NewCall(callRequest *model.CallRequest) call_manager.Call {
	return queue.queueManager.callManager.NewCall(callRequest)
}

func (queue *CallingQueue) NewCallUseResource(callRequest *model.CallRequest, resource ResourceObject) call_manager.Call {
	resource.Take() // rps

	callRequest.Variables = model.UnionStringMaps(
		callRequest.Variables,
		resource.Variables(),
		resource.Gateway().Variables(),
	)

	call := queue.queueManager.callManager.NewCall(callRequest)
	if call.Err() != nil {
		queue.queueManager.SetResourceError(resource, fmt.Sprintf("%d", call.HangupCauseCode()))
	} else {
		queue.queueManager.SetResourceSuccessful(resource)
	}
	return call
}

func (queue *CallingQueue) SetAttemptResult(result *model.AttemptResult) *model.AppError {
	return queue.queueManager.store.Member().Reporting(result.Id, result.Result)
}

func (queue *CallingQueue) GetCallInfoFromAttempt(attempt *Attempt) *AttemptInfoCall {
	if attempt.Info == nil {
		attempt.Info = &AttemptInfoCall{}
	}
	return attempt.Info.(*AttemptInfoCall)
}

func (queue *CallingQueue) AgentMissedCall(agent agent_manager.AgentObject, attempt *Attempt, call call_manager.Call) {
	queue.queueManager.store.Agent().MissedAttempt(agent.Id(), attempt.Id(), call.HangupCause())
}

func (queue *CallingQueue) OfferingAttemptToAgent(a *Attempt, agent agent_manager.AgentObject, display string, agentCallId, memberCallId *string) {
	if agentInfo, err := queue.queueManager.store.Member().AttemptOfferingAgent(a.Id(), display, agentCallId, memberCallId); err != nil {
		wlog.Error(fmt.Sprintf("attempt %d set offering error: %s", a.Id(), err.Error()))
	} else {
		if agentInfo.AgentId != nil {
			ag := model.EventAttempt{
				AttemptId: a.Id(),
				Status:    "offering", //TODO
				AgentId:   agentInfo.AgentId,
				UserId:    model.NewInt64(agent.UserId()),
				Timestamp: agentInfo.Timestamp,
				DomainId:  queue.DomainId(),
			}

			if err = queue.queueManager.mq.AttemptEvent(ag); err != nil {
				wlog.Error(fmt.Sprintf("attempt %d notify offering error: %s", a.Id(), err.Error()))
			}
		}
	}
}

func (queue *CallingQueue) BridgeAttemptToAgent(a *Attempt, agent agent_manager.AgentObject, agentCallId, memberCallId *string) {
	if timestamp, err := queue.queueManager.store.Member().BridgedAttempt(a.Id(), agentCallId, memberCallId); err != nil {
		wlog.Error(fmt.Sprintf("attempt %d set bridge error: %s", a.Id(), err.Error()))
	} else {
		ag := model.EventAttempt{
			AttemptId: a.Id(),
			Status:    "talking", //TODO
			AgentId:   model.NewInt(agent.Id()),
			UserId:    model.NewInt64(agent.UserId()),
			Timestamp: timestamp,
			DomainId:  queue.DomainId(),
		}

		if err = queue.queueManager.mq.AttemptEvent(ag); err != nil {
			wlog.Error(fmt.Sprintf("attempt %d notify bridge error: %s", a.Id(), err.Error()))
		}
	}
}

func (queue *CallingQueue) ReportingAttempt(a *Attempt, agent agent_manager.AgentObject) {
	if timestamp, err := queue.queueManager.store.Member().ReportingAttempt(a.Id()); err != nil {
		wlog.Error(fmt.Sprintf("attempt %d set reporting error: %s", a.Id(), err.Error()))
	} else {
		ag := model.EventAttempt{
			AttemptId: a.Id(),
			Status:    "reporting", //TODO
			AgentId:   model.NewInt(agent.Id()),
			UserId:    model.NewInt64(agent.UserId()),
			Timestamp: timestamp,
			DomainId:  queue.DomainId(),
		}

		if err = queue.queueManager.mq.AttemptEvent(ag); err != nil {
			wlog.Error(fmt.Sprintf("attempt %d notify reporting error: %s", a.Id(), err.Error()))
		}
	}
}

func (queue *CallingQueue) LeavingAttempt(a *Attempt, holdSec int, result *string) {
	//TODO fire event

	if err := queue.queueManager.store.Member().LeavingAttempt(a.Id(), holdSec, result); err != nil {
		wlog.Error(fmt.Sprintf("attempt %d set reporting error: %s", a.Id(), err.Error()))
	}
}
