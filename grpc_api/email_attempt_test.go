package grpc_api

import (
	"context"
	"testing"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"

	"github.com/webitel/call_center/gen/cc"
	"github.com/webitel/call_center/model"
)

func TestEmailAttemptStatus(t *testing.T) {
	cases := map[string]codes.Code{
		model.EmailAttemptErrInvalidArgument:       codes.InvalidArgument,
		model.EmailAttemptErrNotFound:              codes.NotFound,
		model.EmailAttemptErrWakeupRequired:        codes.FailedPrecondition,
		model.EmailAttemptErrOwnerMismatch:         codes.FailedPrecondition,
		model.EmailAttemptErrInvalidState:          codes.FailedPrecondition,
		model.EmailAttemptErrVersionConflict:       codes.Aborted,
		model.EmailAttemptErrSerializationConflict: codes.Aborted,
		model.EmailAttemptErrCommandConflict:       codes.AlreadyExists,
		model.EmailWakeupErrEventConflict:          codes.AlreadyExists,
		model.EmailAttemptErrPostponedLimit:        codes.ResourceExhausted,
		model.EmailAttemptErrSlotExhausted:         codes.ResourceExhausted,
		model.EmailAttemptErrAgentOffline:          codes.FailedPrecondition,
		model.EmailAttemptErrAgentIneligible:       codes.FailedPrecondition,
		model.EmailAttemptErrLockTimeout:           codes.Unavailable,
		model.EmailAttemptErrInternal:              codes.Internal,
	}
	for id, want := range cases {
		err := emailAttemptStatus(context.Background(), model.NewAppError("t", id, nil, "", 500))
		if got := status.Code(err); got != want {
			t.Errorf("%s: got %s, want %s", id, got, want)
		}
		if msg := status.Convert(err).Message(); msg != id {
			t.Errorf("%s: message %q", id, msg)
		}
	}
}

func TestEmailCommandForms(t *testing.T) {
	op := &cc.EmailAttemptOperator{AttemptId: 7, AgentId: 3, ExpectedVersion: proto.Int64(0), CommandId: "c-1"}
	cmd, err := emailOperatorForm(model.EmailAttemptTake, 1, 101, op)
	if err != nil || cmd.Source != model.EmailSourceEngine || *cmd.AttemptId != 7 || *cmd.ExpectedVersion != 0 {
		t.Fatalf("operator form: %+v, %v", cmd, err)
	}
	for name, bad := range map[string]*cc.EmailAttemptOperator{
		"no operator":      nil,
		"no command id":    {AttemptId: 7, AgentId: 3},
		"no agent":         {AttemptId: 7, CommandId: "c"},
		"negative version": {AttemptId: 7, AgentId: 3, ExpectedVersion: proto.Int64(-1), CommandId: "c"},
	} {
		if _, err := emailOperatorForm(model.EmailAttemptTake, 1, 101, bad); status.Code(err) != codes.InvalidArgument {
			t.Errorf("%s: got %v", name, err)
		}
	}

	const event = "0199b2a4-3c4e-7a10-8f2e-1b2c3d4e5f60"
	cmd, err = emailFlowForm(model.EmailAttemptPostpone, 1, 101, &cc.EmailAttemptFlow{EmailEventId: event})
	if err != nil || cmd.Source != model.EmailSourceFlow || cmd.CommandId != event+":postpone" || cmd.AttemptId != nil {
		t.Fatalf("flow form: %+v, %v", cmd, err)
	}
	if _, err = emailFlowForm(model.EmailAttemptPostpone, 1, 101, &cc.EmailAttemptFlow{EmailEventId: "x"}); status.Code(err) != codes.InvalidArgument {
		t.Errorf("flow form without a UUID: %v", err)
	}
}

func TestIsEmailRenewal(t *testing.T) {
	if isEmailRenewal(&cc.AttemptRenewalResultRequest{DomainId: 1, AttemptId: 2, Renewal: 30}) {
		t.Error("a call renewal took the Email path")
	}
	if !isEmailRenewal(&cc.AttemptRenewalResultRequest{DomainId: 1, AttemptId: 2, Renewal: 30, CommandId: "c"}) {
		t.Error("an Email renewal took the old path")
	}
}

func TestEmailResumeForms(t *testing.T) {
	if isEmailResume(&cc.ResumeAttemptRequest{DomainId: 1, AttemptId: 2}) {
		t.Error("a call resume took the Email path")
	}

	api := &member{}
	mixed := &cc.ResumeAttemptRequest{DomainId: 1, ThreadId: 101, AttemptId: 2, EmailEventId: "0199b2a4-3c4e-7a10-8f2e-1b2c3d4e5f60"}
	if _, err := api.emailResume(context.Background(), mixed); status.Code(err) != codes.InvalidArgument {
		t.Errorf("a Flow resume with an attempt: %v", err)
	}
	partial := &cc.ResumeAttemptRequest{DomainId: 1, ThreadId: 101, AttemptId: 2, AgentId: 3}
	if _, err := api.emailResume(context.Background(), partial); status.Code(err) != codes.InvalidArgument {
		t.Errorf("an operator resume without command_id: %v", err)
	}

	err := legacyResumeError(context.Background(), model.NewAppError("QM", model.EmailAttemptErrInvalidArgument, nil, "", 400))
	if status.Code(err) != codes.InvalidArgument {
		t.Errorf("the old form for an Email attempt: %v", err)
	}
}
