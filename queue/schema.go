package queue

import (
	"fmt"
	"github.com/webitel/call_center/model"
	flow "github.com/webitel/protos/workflow"
	"github.com/webitel/wlog"
)

type DoDistributeResult struct {
	Destination   string
	DisplayNumber string
	Variables     map[string]interface{}
	Cancel        bool
}

func (qm *QueueManager) DoDistributeSchema(queue *BaseQueue, att *Attempt) bool {
	if queue.doSchema == nil {

		return true
	}

	res, err := qm.app.FlowManager().Queue().DoDistributeAttempt(&flow.DistributeAttemptRequest{
		DomainId:  queue.domainId,
		SchemaId:  *queue.doSchema,
		Variables: att.ExportSchemaVariables(),
	})

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

func (qm *QueueManager) AfterDistributeSchema(queue *BaseQueue, att *Attempt) {
	fmt.Println("TEST AfterDistributeSchema")
}
