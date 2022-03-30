package queue

import (
	"fmt"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
	flow "github.com/webitel/protos/workflow"
	"github.com/webitel/wlog"
	"time"
)

type DoDistributeResult struct {
	Destination   string
	DisplayNumber string
	Variables     map[string]interface{}
	Cancel        bool
}

type SchemaResult struct {
	Status             string
	MaxAttempts        uint32
	WaitBetweenRetries uint32
	Variables          map[string]string
}

func (qm *QueueManager) DoDistributeSchema(queue *BaseQueue, att *Attempt) bool {
	if queue.doSchema == nil {

		return true
	}

	st := time.Now()

	res, err := qm.app.FlowManager().Queue().DoDistributeAttempt(&flow.DistributeAttemptRequest{
		DomainId:  queue.domainId,
		SchemaId:  *queue.doSchema,
		Variables: att.ExportSchemaVariables(),
	})

	if err != nil {
		att.Log(fmt.Sprintf("DoDistributeAttempt error=%s duration=%s", err.Error(), time.Since(st)))
		wlog.Error(fmt.Sprintf("%s", err.Error()))
		return true
	}

	att.Log(fmt.Sprintf("DoDistributeAttempt job_id=%s duration=%s", res.Id, time.Since(st)))

	switch res.Result.(type) {
	case *flow.DistributeAttemptResponse_Cancel_:
		v := res.Result.(*flow.DistributeAttemptResponse_Cancel_).Cancel
		if err := qm.store.Member().SetDistributeCancel(att.Id(), v.Description, v.NextDistributeSec, v.Stop, res.Variables); err != nil {
			wlog.Error(fmt.Sprintf("attempt [%d] error: %s", att.Id(), err.Error()))
		}

		return false
	case *flow.DistributeAttemptResponse_Confirm_:
		v := res.Result.(*flow.DistributeAttemptResponse_Confirm_).Confirm
		if v.Destination != "" {
			att.communication.Destination = v.Destination
		}

		if v.Display != "" {
			att.communication.Display = model.NewString(v.Display)
		}
	default:
		// TODO
	}

	if res.Variables != nil {
		for k, v := range res.Variables {
			att.member.Variables[k] = v
		}
	}

	return true
}

func (qm *QueueManager) SendAfterDistributeSchema(attempt *Attempt) bool {
	if res, ok := attempt.AfterDistributeSchema(); ok {
		if res.Status == AttemptResultSuccess {
			qm.SetAttemptSuccess(attempt, res.Variables)
		} else {
			qm.SetAttemptAbandonedWithParams(attempt, attempt.maxAttempts, attempt.waitBetween, res.Variables)
		}

		qm.LeavingMember(attempt)
		return true
	}

	return false
}

func (qm *QueueManager) AfterDistributeSchema(att *Attempt) (*SchemaResult, bool) {
	if att.queue == nil || att.queue.AfterSchemaId() == nil {

		return nil, false
	}

	var vars map[string]string

	if att.memberChannel != nil {
		vars = att.memberChannel.Stats()
	}

	call_manager.DUMP(model.UnionStringMaps(
		att.ExportSchemaVariables(),
		vars,
	))

	st := time.Now()

	res, err := qm.app.FlowManager().Queue().ResultAttempt(&flow.ResultAttemptRequest{
		DomainId: att.queue.DomainId(),
		SchemaId: *att.queue.AfterSchemaId(),
		Variables: model.UnionStringMaps(
			att.ExportSchemaVariables(),
			vars,
		),
	})

	if err != nil {
		// TODO
		wlog.Error(fmt.Sprintf("AfterDistributeSchema error: %s duration=%s", err.Error(), time.Since(st)))
		return nil, false
	}

	att.Log(fmt.Sprintf("AfterDistributeSchema job_id=%s duration=%s", res.Id, time.Since(st)))

	switch v := res.Result.(type) {
	case *flow.ResultAttemptResponse_Success_:
		return &SchemaResult{
			Status:    AttemptResultSuccess,
			Variables: res.Variables,
		}, true

	case *flow.ResultAttemptResponse_Abandoned_:
		return &SchemaResult{
			Status:             v.Abandoned.Status,
			MaxAttempts:        v.Abandoned.MaxAttempts,
			WaitBetweenRetries: v.Abandoned.WaitBetweenRetries,
			Variables:          res.Variables,
		}, true

	}

	return nil, false
}
