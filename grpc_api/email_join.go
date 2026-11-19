package grpc_api

import (
	"context"
	"errors"
	"fmt"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/webitel/call_center/app"
	"github.com/webitel/call_center/gen/cc"
	"github.com/webitel/call_center/model"
)

// EmailJoinToQueue maps the request to model.EmailJoin, which validates itself in the Manager.
func (api *member) EmailJoinToQueue(ctx context.Context, in *cc.EmailJoinToQueueRequest) (*cc.EmailJoinToQueueResponse, error) {
	join := model.EmailJoin{
		EventId:         in.GetEmailEventId(),
		DomainId:        in.GetDomainId(),
		ThreadId:        in.GetThreadId(),
		QueueId:         in.GetQueueId(),
		Priority:        in.GetPriority(),
		StickyAgentId:   in.GetStickyAgentId(),
		ExtraEmailCount: in.GetExtraEmailCount(),
		FromAddress:     in.GetFromAddress(),
	}

	res, err := api.app.Queue().Manager().EmailJoinToQueue(ctx, join)
	if err != nil {
		return nil, newEmailJoinError(ctx, join, err)
	}

	return &cc.EmailJoinToQueueResponse{
		AttemptId: res.AttemptId,
		QueueId:   res.QueueId,
		Result:    emailJoinResult(res.Result),
	}, nil
}

// emailJoinError answers with the gRPC code and the stable error id flow_manager matches,
// where the interceptor would send the AppError as JSON. Error() keeps the full AppError
// and the call, so the interceptor logs the failure once with its cause.
type emailJoinError struct {
	err     *model.AppError
	join    model.EmailJoin
	code    codes.Code
	message string
}

func newEmailJoinError(ctx context.Context, join model.EmailJoin, err *model.AppError) *emailJoinError {
	e := &emailJoinError{err: err, join: join, code: app.HTTPCodeToGRPC(err.StatusCode), message: err.Id}
	if ctxErr := ctx.Err(); ctxErr != nil {
		e.code, e.message = codes.Canceled, ctxErr.Error()
		if errors.Is(ctxErr, context.DeadlineExceeded) {
			e.code = codes.DeadlineExceeded
		}
	}

	return e
}

func (e *emailJoinError) Error() string {
	return fmt.Sprintf("email join event_id=%s domain_id=%d thread_id=%d requested_queue_id=%d: %s",
		e.join.EventId, e.join.DomainId, e.join.ThreadId, e.join.QueueId, e.err.Error())
}

func (e *emailJoinError) GRPCStatus() *status.Status {
	return status.New(e.code, e.message)
}

func emailJoinResult(result string) cc.EmailJoinToQueueResponse_Result {
	switch result {
	case model.EmailJoinCreated:
		return cc.EmailJoinToQueueResponse_RESULT_CREATED
	case model.EmailJoinAlreadyActive:
		return cc.EmailJoinToQueueResponse_RESULT_ALREADY_ACTIVE
	case model.EmailJoinReplayed:
		return cc.EmailJoinToQueueResponse_RESULT_REPLAYED
	default:
		return cc.EmailJoinToQueueResponse_RESULT_UNSPECIFIED
	}
}
