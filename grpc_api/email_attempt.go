package grpc_api

import (
	"context"
	"errors"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/webitel/call_center/gen/cc"
	"github.com/webitel/call_center/model"
)

const maxEmailCommandId = 128

var errEmailCommandForm = status.Error(codes.InvalidArgument,
	"domain_id, thread_id and an operator with attempt_id, agent_id, expected_version and command_id are required")

func (api *member) EmailAttemptTake(ctx context.Context, in *cc.EmailAttemptTakeRequest) (*cc.EmailAttemptResponse, error) {
	return api.emailOperatorCommand(ctx, model.EmailAttemptTake, in.GetDomainId(), in.GetThreadId(), in.GetOperator())
}

func (api *member) EmailAttemptReturn(ctx context.Context, in *cc.EmailAttemptReturnRequest) (*cc.EmailAttemptResponse, error) {
	return api.emailOperatorCommand(ctx, model.EmailAttemptReturn, in.GetDomainId(), in.GetThreadId(), in.GetOperator())
}

func (api *member) EmailAttemptComplete(ctx context.Context, in *cc.EmailAttemptCompleteRequest) (*cc.EmailAttemptResponse, error) {
	return api.emailOperatorCommand(ctx, model.EmailAttemptComplete, in.GetDomainId(), in.GetThreadId(), in.GetOperator())
}

// EmailAttemptPostpone takes the caller from the request form: an operator or a Flow, never a field.
func (api *member) EmailAttemptPostpone(ctx context.Context, in *cc.EmailAttemptPostponeRequest) (*cc.EmailAttemptResponse, error) {
	var cmd model.EmailAttemptCommand
	var err error
	switch caller := in.GetCaller().(type) {
	case *cc.EmailAttemptPostponeRequest_Operator:
		cmd, err = emailOperatorForm(model.EmailAttemptPostpone, in.GetDomainId(), in.GetThreadId(), caller.Operator)
	case *cc.EmailAttemptPostponeRequest_Flow:
		cmd, err = emailFlowForm(model.EmailAttemptPostpone, in.GetDomainId(), in.GetThreadId(), caller.Flow)
	default:
		err = errEmailCommandForm
	}
	if err != nil {
		return nil, err
	}

	switch d := in.GetDeadline().(type) {
	case *cc.EmailAttemptPostponeRequest_PostponedUntil:
		if d.PostponedUntil <= 0 {
			return nil, status.Error(codes.InvalidArgument, "postponed_until must be positive Unix milliseconds")
		}
		t := time.UnixMilli(d.PostponedUntil).UTC()
		cmd.PostponedUntil = &t
	case *cc.EmailAttemptPostponeRequest_PostponeForSec:
		if d.PostponeForSec <= 0 {
			return nil, status.Error(codes.InvalidArgument, "postpone_for_sec must be positive")
		}
		cmd.PostponeForSec = &d.PostponeForSec
	default:
		return nil, status.Error(codes.InvalidArgument, "postponed_until or postpone_for_sec is required")
	}

	return api.emailAttemptCommand(ctx, cmd)
}

func (api *member) emailOperatorCommand(ctx context.Context, op string, domainId, threadId int64, operator *cc.EmailAttemptOperator) (*cc.EmailAttemptResponse, error) {
	cmd, err := emailOperatorForm(op, domainId, threadId, operator)
	if err != nil {
		return nil, err
	}

	return api.emailAttemptCommand(ctx, cmd)
}

// emailOperatorRenewal renews the processing deadline of an Email attempt; other attempts keep the old path.
func (api *member) emailOperatorRenewal(ctx context.Context, in *cc.AttemptRenewalResultRequest) (*cc.AttemptRenewalResultResponse, error) {
	cmd, err := emailOperatorForm(model.EmailAttemptRenew, in.GetDomainId(), in.GetThreadId(), &cc.EmailAttemptOperator{
		AttemptId:       in.GetAttemptId(),
		AgentId:         in.GetAgentId(),
		ExpectedVersion: in.ExpectedVersion,
		CommandId:       in.GetCommandId(),
	})
	if err != nil {
		return nil, err
	}
	if in.GetRenewal() == 0 || in.GetRenewal() > 1<<31-1 {
		return nil, status.Error(codes.InvalidArgument, "renewal must be a positive number of seconds")
	}
	sec := int32(in.GetRenewal())
	cmd.RenewalSec = &sec

	res, err := api.emailAttemptCommand(ctx, cmd)
	if err != nil {
		return nil, err
	}

	return &cc.AttemptRenewalResultResponse{Email: res}, nil
}

// emailResume resumes a postponed Email attempt: by its agent, or by a Flow with the event that woke it.
func (api *member) emailResume(ctx context.Context, in *cc.ResumeAttemptRequest) (*cc.ResumeAttemptResponse, error) {
	var cmd model.EmailAttemptCommand
	var err error
	if in.GetEmailEventId() != "" {
		if in.GetAttemptId() != 0 || in.GetAgentId() != 0 || in.ExpectedVersion != nil || in.GetCommandId() != "" {
			return nil, status.Error(codes.InvalidArgument, "a Flow resume sets only domain_id, thread_id and email_event_id")
		}
		cmd, err = emailFlowForm(model.EmailAttemptResume, in.GetDomainId(), in.GetThreadId(), &cc.EmailAttemptFlow{EmailEventId: in.GetEmailEventId()})
	} else {
		cmd, err = emailOperatorForm(model.EmailAttemptResume, in.GetDomainId(), in.GetThreadId(), &cc.EmailAttemptOperator{
			AttemptId:       in.GetAttemptId(),
			AgentId:         in.GetAgentId(),
			ExpectedVersion: in.ExpectedVersion,
			CommandId:       in.GetCommandId(),
		})
	}
	if err != nil {
		return nil, err
	}

	res, err := api.emailAttemptCommand(ctx, cmd)
	if err != nil {
		return nil, err
	}

	return &cc.ResumeAttemptResponse{Ok: true, Email: res}, nil
}

// legacyResumeError tells a caller of the old form that an Email attempt needs the Email form,
// or that the Email check failed; other errors of the old path are kept.
func legacyResumeError(ctx context.Context, err *model.AppError) error {
	if err.Id == model.EmailAttemptErrInvalidArgument || err.Id == model.EmailAttemptErrUnavailable {
		return emailAttemptStatus(ctx, err)
	}

	return err
}

func isEmailResume(in *cc.ResumeAttemptRequest) bool {
	return in.GetThreadId() != 0 || in.GetAgentId() != 0 || in.ExpectedVersion != nil ||
		in.GetCommandId() != "" || in.GetEmailEventId() != ""
}

func isEmailRenewal(in *cc.AttemptRenewalResultRequest) bool {
	return in.GetThreadId() != 0 || in.GetAgentId() != 0 || in.ExpectedVersion != nil || in.GetCommandId() != ""
}

// emailOperatorForm needs expected_version present; an explicit 0 is a real version.
func emailOperatorForm(op string, domainId, threadId int64, o *cc.EmailAttemptOperator) (model.EmailAttemptCommand, error) {
	if domainId <= 0 || threadId <= 0 || o == nil || o.GetAttemptId() <= 0 || o.GetAgentId() <= 0 ||
		o.ExpectedVersion == nil || o.GetExpectedVersion() < 0 || o.GetCommandId() == "" || len(o.GetCommandId()) > maxEmailCommandId {
		return model.EmailAttemptCommand{}, errEmailCommandForm
	}

	attemptId, agentId, version := o.GetAttemptId(), o.GetAgentId(), o.GetExpectedVersion()
	return model.EmailAttemptCommand{
		Op:              op,
		Source:          model.EmailSourceEngine,
		CommandId:       o.GetCommandId(),
		DomainId:        domainId,
		ThreadId:        threadId,
		AttemptId:       &attemptId,
		AgentId:         &agentId,
		ExpectedVersion: &version,
	}, nil
}

// emailFlowForm keys the command by the event that woke the Thread, so a Flow retry is deduplicated.
func emailFlowForm(op string, domainId, threadId int64, f *cc.EmailAttemptFlow) (model.EmailAttemptCommand, error) {
	if domainId <= 0 || threadId <= 0 || f == nil || !emailEventIdRe.MatchString(f.GetEmailEventId()) {
		return model.EmailAttemptCommand{}, status.Error(codes.InvalidArgument, "domain_id, thread_id and a UUID email_event_id are required")
	}

	eventId := f.GetEmailEventId()
	return model.EmailAttemptCommand{
		Op:           op,
		Source:       model.EmailSourceFlow,
		CommandId:    eventId + ":" + op,
		DomainId:     domainId,
		ThreadId:     threadId,
		EmailEventId: &eventId,
	}, nil
}

func (api *member) emailAttemptCommand(ctx context.Context, cmd model.EmailAttemptCommand) (*cc.EmailAttemptResponse, error) {
	res, err := api.app.Queue().Manager().EmailAttemptCommand(ctx, cmd)
	if err != nil {
		return nil, emailAttemptStatus(ctx, err)
	}

	return emailAttemptResponse(res), nil
}

func emailAttemptResponse(res *model.EmailAttemptResult) *cc.EmailAttemptResponse {
	out := &cc.EmailAttemptResponse{
		AttemptId:         res.AttemptId,
		ThreadId:          res.ThreadId,
		State:             res.State,
		AttemptVersion:    res.AttemptVersion,
		ProjectionVersion: res.ProjectionVersion,
		QueueId:           res.QueueId,
		Replayed:          res.Replayed,
	}
	if res.Result != nil {
		out.Result = *res.Result
	}
	if res.AgentId != nil {
		out.AgentId = *res.AgentId
	}
	if res.PostponedUntil != nil {
		out.PostponedUntil = res.PostponedUntil.UnixMilli()
	}

	return out
}

// emailAttemptStatus maps stable error ids to gRPC codes; the message carries the id.
func emailAttemptStatus(ctx context.Context, err *model.AppError) error {
	if ctxErr := ctx.Err(); ctxErr != nil {
		if errors.Is(ctxErr, context.DeadlineExceeded) {
			return status.Error(codes.DeadlineExceeded, ctxErr.Error())
		}
		return status.Error(codes.Canceled, ctxErr.Error())
	}

	code := codes.Internal
	switch err.Id {
	case model.EmailAttemptErrInvalidArgument:
		code = codes.InvalidArgument
	case model.EmailAttemptErrNotFound:
		code = codes.NotFound
	case model.EmailAttemptErrWakeupRequired, model.EmailAttemptErrOwnerMismatch, model.EmailAttemptErrInvalidState,
		model.EmailAttemptErrAgentOffline, model.EmailAttemptErrAgentIneligible:
		code = codes.FailedPrecondition
	case model.EmailAttemptErrVersionConflict, model.EmailAttemptErrSerializationConflict, model.EmailAttemptErrDeadlock:
		code = codes.Aborted
	case model.EmailAttemptErrCommandConflict, model.EmailWakeupErrEventConflict:
		code = codes.AlreadyExists
	case model.EmailAttemptErrPostponedLimit, model.EmailAttemptErrProlongationLimit, model.EmailAttemptErrSlotExhausted:
		code = codes.ResourceExhausted
	case model.EmailAttemptErrLockTimeout, model.EmailAttemptErrUnavailable:
		code = codes.Unavailable
	}

	return status.Error(code, err.Id)
}

// EmailWakeUp is called by flow_manager for every inbound Email event before its Flow.
func (api *member) EmailWakeUp(ctx context.Context, in *cc.EmailWakeUpRequest) (*cc.EmailWakeUpResponse, error) {
	if in.GetDomainId() <= 0 || in.GetThreadId() <= 0 || !emailEventIdRe.MatchString(in.GetEmailEventId()) {
		return nil, status.Error(codes.InvalidArgument, "domain_id, thread_id and a UUID email_event_id are required")
	}

	res, err := api.app.Queue().Manager().EmailWakeUp(ctx, model.EmailWakeUp{
		EventId:  in.GetEmailEventId(),
		DomainId: in.GetDomainId(),
		ThreadId: in.GetThreadId(),
	})
	if err != nil {
		return nil, emailAttemptStatus(ctx, err)
	}

	out := &cc.EmailWakeUpResponse{Result: emailWakeUpResult(res.Result), Replayed: res.Replayed}
	if res.AttemptId != nil {
		out.AttemptId = *res.AttemptId
	}
	if res.AttemptState != nil {
		out.State = *res.AttemptState
	}
	if res.AttemptVersion != nil {
		out.AttemptVersion = *res.AttemptVersion
	}
	out.FallbackQueueId = res.FallbackQueueId

	return out, nil
}

func emailWakeUpResult(result string) cc.EmailWakeUpResponse_Result {
	switch result {
	case model.EmailWakeupWoken:
		return cc.EmailWakeUpResponse_RESULT_WOKEN
	case model.EmailWakeupQueued:
		return cc.EmailWakeUpResponse_RESULT_QUEUED
	case model.EmailWakeupReopened:
		return cc.EmailWakeUpResponse_RESULT_REOPENED
	case model.EmailWakeupNoop:
		return cc.EmailWakeUpResponse_RESULT_NOOP
	case model.EmailWakeupNotActive:
		return cc.EmailWakeUpResponse_RESULT_NOT_ACTIVE
	default:
		return cc.EmailWakeUpResponse_RESULT_UNSPECIFIED
	}
}
