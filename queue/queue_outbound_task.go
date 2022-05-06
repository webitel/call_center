package queue

import (
	"encoding/json"
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/protos/workflow"
	"github.com/webitel/wlog"
)

type TaskOutboundQueueSettings struct {
	BaseQueue
	OriginateTimeout       int    `json:"originate_timeout"`
	MaxAttempts            uint   `json:"max_attempts"`
	WaitBetweenRetries     uint64 `json:"wait_between_retries"`
	WaitBetweenRetriesDesc bool   `json:"wait_between_retries_desc"`
}

type TaskOutboundQueue struct {
	BaseQueue
	TaskOutboundQueueSettings
}

func NewTaskOutboundQueue(base BaseQueue, settings TaskOutboundQueueSettings) QueueObject {
	return &TaskOutboundQueue{
		BaseQueue:                 base,
		TaskOutboundQueueSettings: settings,
	}
}

func TaskOutboundQueueSettingsFromBytes(data []byte) TaskOutboundQueueSettings {
	var settings TaskOutboundQueueSettings
	json.Unmarshal(data, &settings)
	return settings
}

func (queue *TaskOutboundQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	go queue.run(attempt)
	return nil
}

func (queue *TaskOutboundQueue) run(attempt *Attempt) {
	if !queue.queueManager.DoDistributeSchema(&queue.BaseQueue, attempt) {
		queue.queueManager.LeavingMember(attempt)
		return
	}

	attempt.SetState(model.MemberStateJoined)

	_, err := queue.queueManager.store.Member().SetAttemptBridged(attempt.Id())
	if err != nil {
		wlog.Error(err.Error())
	}
	attempt.SetState(model.MemberStateBridged)

	if queue.schemaId != nil {
		queue.execSchema(attempt, *queue.schemaId)
	}

	queue.queueManager.SetAttemptSuccess(attempt, nil)
	queue.queueManager.LeavingMember(attempt)
}

func (queue *TaskOutboundQueue) execSchema(attempt *Attempt, schemaId int) {
	// add params last attempt
	req := &workflow.StartSyncFlowRequest{
		SchemaId:   uint32(schemaId),
		TimeoutSec: uint64(queue.OriginateTimeout),
		DomainId:   queue.DomainId(),
		Variables: model.UnionStringMaps(
			attempt.ExportSchemaVariables(),
			queue.variables,
			map[string]string{
				"state":   attempt.GetState(),
				"channel": queue.channel,
			},
		),
	}

	if id, e := queue.queueManager.app.FlowManager().Queue().StartSyncFlow(req); e != nil {
		attempt.Log(fmt.Sprintf("schema error: %s", e.Error()))
	} else {
		attempt.Log(fmt.Sprintf("schema exucetted id=%s", id))
	}

	if res, ok := attempt.AfterDistributeSchema(); ok {
		if res.Status == AttemptResultSuccess {
			queue.queueManager.SetAttemptSuccess(attempt, res.Variables)
		} else {
			queue.queueManager.SetAttemptAbandonedWithParams(attempt, attempt.maxAttempts, attempt.waitBetween, res.Variables)
		}

		queue.queueManager.LeavingMember(attempt)
		return
	}
}
