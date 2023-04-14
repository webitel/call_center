package queue

import (
	"errors"
	"fmt"
	"github.com/webitel/call_center/model"
	flow "github.com/webitel/protos/workflow"
	"github.com/webitel/wlog"
	"golang.org/x/sync/singleflight"
	"time"
)

var (
	formActionGroupRequest singleflight.Group
)

type DoDistributeResult struct {
	Destination   string
	DisplayNumber string
	Variables     map[string]interface{}
	Cancel        bool
}

func (qm *QueueManager) StartProcessingForm(schemaId int, att *Attempt) {
	if schemaId == 0 {
		return
	}

	att.MarkProcessingFormStarted()

	pf, err := qm.app.FlowManager().Queue().NewProcessing(att.Context, att.domainId, schemaId, att.ExportSchemaVariables())
	if err != nil {
		//TODO ERROR FIXME
		att.Log(fmt.Sprintf("set form error: %s", err.Error()))
		return
	}
	if err := qm.store.Member().StoreForm(att.Id(), pf.Form(), pf.Fields()); err != nil {
		//TODO ERROR FIXME
		att.Log(fmt.Sprintf("set form error: %s", err.Error()))
		return
	}
	att.processingForm = pf
	e := NewNextFormEvent(att, att.agent.UserId())
	appErr := qm.mq.AgentChannelEvent(att.channel, att.domainId, att.QueueId(), att.agent.UserId(), e)
	if appErr != nil {
		wlog.Error(err.Error())
	}
}

func (qm *QueueManager) AttemptProcessingActionForm(attemptId int64, action string, fields map[string]string) error {
	_, err, _ := formActionGroupRequest.Do(fmt.Sprintf("action-%d", attemptId), func() (interface{}, error) {
		return nil, qm.attemptProcessingActionForm(attemptId, action, fields)
	})

	return err
}

func (qm *QueueManager) attemptProcessingActionForm(attemptId int64, action string, fields map[string]string) error {

	wlog.Debug(fmt.Sprintf("attempt[%d] action form: %v (%v)", attemptId, attemptId, fields))

	attempt, _ := qm.GetAttempt(attemptId)
	if attempt == nil {
		//TODO ERRoR
		return errors.New("not found")
	}

	if attempt.processingForm != nil && attempt.agent != nil {
		_, err := attempt.processingForm.ActionForm(attempt.Context, action, fields)
		if err != nil {
			attempt.Log(err.Error())
			attempt.processingForm = nil // todo lock
		} else {
			// todo
			if attempt.processingForm == nil {
				attempt.Log("processingForm is null!!1 LOCK")
				return nil
			}
			if appErr := qm.store.Member().StoreForm(attempt.Id(), attempt.processingForm.Form(), attempt.processingForm.Fields()); appErr != nil {
				attempt.Log(fmt.Sprintf("set form error: %s", appErr.Error()))
				return nil
			}
		}

		e := NewNextFormEvent(attempt, attempt.agent.UserId())
		appErr := qm.mq.AgentChannelEvent(attempt.channel, attempt.domainId, attempt.QueueId(), attempt.agent.UserId(), e)
		if appErr != nil {
			wlog.Error(appErr.Error())
			return appErr
		}
	}
	return nil
}

func (qm *QueueManager) DoDistributeSchema(queue *BaseQueue, att *Attempt) bool {
	if queue.doSchema == nil {

		return true
	}

	st := time.Now()

	res, err := qm.app.FlowManager().Queue().DoDistributeAttempt(&flow.DistributeAttemptRequest{
		DomainId: queue.domainId,
		SchemaId: *queue.doSchema,
		Variables: model.UnionStringMaps(
			queue.Variables(),
			att.ExportSchemaVariables(),
		),
	})

	if err != nil {
		att.Log(fmt.Sprintf("DoDistributeAttempt error=%s duration=%s", err.Error(), time.Since(st)))
		wlog.Error(fmt.Sprintf("%s", err.Error()))
		return true
	}

	att.Log(fmt.Sprintf("DoDistributeAttempt job_id=%s duration=%s", res.Id, time.Since(st)))

	confirm := false

	switch res.Result.(type) {
	case *flow.DistributeAttemptResponse_Cancel_:
		v := res.Result.(*flow.DistributeAttemptResponse_Cancel_).Cancel
		if err := qm.store.Member().SetDistributeCancel(att.Id(), v.Description, v.NextDistributeSec, v.Stop, res.Variables); err != nil {
			wlog.Error(fmt.Sprintf("attempt [%d] error: %s", att.Id(), err.Error()))
		}
	case *flow.DistributeAttemptResponse_Confirm_:
		v := res.Result.(*flow.DistributeAttemptResponse_Confirm_).Confirm
		if v.Destination != "" {
			att.communication.Destination = v.Destination
		}

		if v.Display != "" {
			att.communication.Display = model.NewString(v.Display)
		}
		confirm = true
	default:
		// TODO
	}

	if res.Variables != nil {
		att.AddVariables(res.Variables)
	}

	return confirm
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

func (qm *QueueManager) AfterDistributeSchema(att *Attempt) (*model.SchemaResult, bool) {
	if att.queue == nil || att.queue.AfterSchemaId() == nil {

		return nil, false
	}

	var vars map[string]string

	if att.memberChannel != nil {
		vars = att.memberChannel.Stats()
	}

	st := time.Now()

	res, err := qm.app.FlowManager().Queue().ResultAttempt(&flow.ResultAttemptRequest{
		DomainId: att.queue.DomainId(),
		SchemaId: *att.queue.AfterSchemaId(),
		Variables: model.UnionStringMaps(
			att.queue.Variables(),
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
		return &model.SchemaResult{
			Type:      model.SchemaResultTypeSuccess,
			Status:    AttemptResultSuccess,
			Variables: res.Variables,
		}, true

	case *flow.ResultAttemptResponse_Abandoned_:
		return &model.SchemaResult{
			Type:                 model.SchemaResultTypeAbandoned,
			Status:               v.Abandoned.Status,
			MaxAttempts:          v.Abandoned.MaxAttempts,
			WaitBetweenRetries:   v.Abandoned.WaitBetweenRetries,
			ExcludeCurrentNumber: v.Abandoned.ExcludeCurrentCommunication,
			Redial:               v.Abandoned.Redial,
			Variables:            res.Variables,
			AgentId:              v.Abandoned.AgentId,
			Display:              v.Abandoned.Display,
			Description:          v.Abandoned.Description,
		}, true

	case *flow.ResultAttemptResponse_Retry_:
		return &model.SchemaResult{
			Type:              model.SchemaResultTypeRetry,
			RetrySleep:        v.Retry.Sleep,
			RetryNextResource: v.Retry.NextResource,
			RetryResourceId:   v.Retry.ResourceId,
		}, true

	}

	return nil, false
}
