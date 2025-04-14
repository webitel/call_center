package queue

import (
	flow "buf.build/gen/go/webitel/workflow/protocolbuffers/go"
	"context"
	"errors"
	"fmt"
	"github.com/webitel/call_center/model"
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

func (qm *Manager) StartProcessingForm(schemaId int, att *Attempt) {
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

	// TODO DEV-4420, implement mx
	agent := att.Agent()
	if agent == nil {
		att.Log("set form error: not found agent")
		return
	}

	e := NewNextFormEvent(att, agent.UserId())
	appErr := qm.mq.AgentChannelEvent(att.channel, att.domainId, att.QueueId(), agent.UserId(), e)
	if appErr != nil {
		att.log.Error(appErr.Error(),
			wlog.Err(err),
		)
	}
}

func (qm *Manager) AttemptProcessingActionForm(attemptId int64, action string, fields map[string]string) error {
	_, err, _ := formActionGroupRequest.Do(fmt.Sprintf("form-%d", attemptId), func() (interface{}, error) {
		return nil, qm.attemptProcessingActionForm(attemptId, action, fields)
	})

	return err
}

func (qm *Manager) attemptProcessingActionForm(attemptId int64, action string, fields map[string]string) error {

	qm.log.Debug(fmt.Sprintf("attempt[%d] action form: %v (%v)", attemptId, attemptId, fields),
		wlog.Int64("attempt_id", attemptId),
		wlog.String("action", action),
	)

	attempt, _ := qm.GetAttempt(attemptId)
	if attempt == nil {
		//TODO ERRoR
		return errors.New("not found")
	}

	if attempt.processingForm != nil && attempt.agent != nil {
		attempt.UpdateProcessingFields(fields)
		_, err := attempt.processingForm.ActionForm(attempt.Context, action, fields)
		if err != nil {
			attempt.Log(err.Error())
			attempt.processingForm = nil // todo lock
			printfIfErr(qm.store.Member().StoreFormFields(attempt.Id(), fields))
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
			attempt.log.Error(appErr.Error(),
				wlog.Err(appErr),
			)
			return appErr
		}
	}
	return nil
}

func (qm *Manager) AttemptProcessingActionComponent(ctx context.Context, attemptId int64, formId, component string, action string, vars map[string]string) error {
	_, err, _ := formActionGroupRequest.Do(fmt.Sprintf("component-%d", attemptId), func() (interface{}, error) {

		qm.log.Debug(fmt.Sprintf("attempt[%d] action component: %v (%v)", attemptId, attemptId, vars),
			wlog.Int64("attempt_id", attemptId),
			wlog.String("action", action),
			wlog.String("component", component),
		)

		attempt, _ := qm.GetAttempt(attemptId)
		if attempt == nil {
			return nil, errors.New("not found")
		}
		if attempt.processingForm != nil && attempt.agent != nil {
			return nil, attempt.processingForm.ActionComponent(ctx, formId, component, action, vars)
		}

		return nil, nil
	})

	if err != nil {
		return err
	}

	return nil
}

func (qm *Manager) DoDistributeSchema(queue *BaseQueue, att *Attempt) bool {
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
		att.log.Error(err.Error(),
			wlog.Err(err),
		)
		return true
	}

	att.Log(fmt.Sprintf("DoDistributeAttempt job_id=%s duration=%s", res.Id, time.Since(st)))

	confirm := false

	switch res.Result.(type) {
	case *flow.DistributeAttemptResponse_Cancel_:
		v := res.Result.(*flow.DistributeAttemptResponse_Cancel_).Cancel
		if err := qm.store.Member().SetDistributeCancel(att.Id(), v.Description, v.NextDistributeSec, v.Stop, res.Variables); err != nil {
			att.log.Error(fmt.Sprintf("attempt [%d] error: %s", att.Id(), err.Error()),
				wlog.Err(err),
			)
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
		confirm = true
		att.Log("warn: bad pre-schema, set default confirm attempt")
	}

	if res.Variables != nil {
		att.AddVariables(res.Variables)
	}

	return confirm
}

func (qm *Manager) SendAfterDistributeSchema(attempt *Attempt) bool {
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

func (qm *Manager) AfterDistributeSchema(att *Attempt) (*model.SchemaResult, bool) {
	if att.queue == nil || att.queue.AfterSchemaId() == nil {

		return nil, false
	}

	var vars map[string]string

	if att.memberChannel != nil {
		vars = att.memberChannel.Stats()
	}

	st := time.Now()

	// TODO WTEL-4153
	if att.Result() == "" && att.memberChannel != nil {
		if att.agentChannel != nil && att.agentChannel.Answered() && att.memberChannel.Answered() {
			vars["cc_result"] = "success"
		} else {
			vars["cc_result"] = "abandoned"
		}

		if !att.memberChannel.Answered() {
			vars["cc_result"] = "failed"
		}
	}

	var sc *flow.FlowScope
	if att.channel == model.QueueChannelCall && att.memberChannel != nil {
		sc = &flow.FlowScope{
			Channel: att.channel,
			Id:      att.memberChannel.Id(),
		}
	}

	res, err := qm.app.FlowManager().Queue().ResultAttempt(&flow.ResultAttemptRequest{
		DomainId: att.queue.DomainId(),
		SchemaId: *att.queue.AfterSchemaId(),
		Scope:    sc,
		Variables: model.UnionStringMaps(
			att.queue.Variables(),
			att.ExportSchemaVariables(),
			vars,
		),
	})

	if err != nil {
		// TODO
		att.log.Error(fmt.Sprintf("AfterDistributeSchema [%d] error: %s duration=%s", att.Id(), err.Error(), time.Since(st)),
			wlog.Err(err),
		)
		return nil, false
	}

	att.Log(fmt.Sprintf("AfterDistributeSchema [%d] job_id=%s duration=%s", att.Id(), res.Id, time.Since(st)))

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
