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

	att.Log(fmt.Sprintf("DoDistributeAttempt duration %s", time.Since(st)))

	if err != nil {
		// TODO
		wlog.Error(fmt.Sprintf("%s", err.Error()))
		return true
	}

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

func (qm *QueueManager) AfterDistributeSchema(queue *BaseQueue, att *Attempt, call call_manager.Call) (*SchemaResult, bool) {
	if queue.afterSchemaId == nil {

		return nil, false
	}

	vars := call.Stats()

	call_manager.DUMP(model.UnionStringMaps(
		att.ExportSchemaVariables(),
		vars,
	))

	res, err := qm.app.FlowManager().Queue().ResultAttempt(&flow.ResultAttemptRequest{
		DomainId: queue.domainId,
		SchemaId: *queue.afterSchemaId,
		Variables: model.UnionStringMaps(
			att.ExportSchemaVariables(),
			vars,
		),
	})

	if err != nil {
		// TODO
		wlog.Error(fmt.Sprintf("%s", err.Error()))
		return nil, false
	}

	switch v := res.Result.(type) {
	case *flow.ResultAttemptResponse_Success_:
		return &SchemaResult{
			Status:    "success",
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
