package grpc_api

import (
	"context"
	"errors"
	"net/http"
	"regexp"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/webitel/call_center/gen/cc"
	"github.com/webitel/call_center/model"
)

var emailEventIdRe = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

// EmailJoinToQueue returns gRPC statuses itself: the shared AppError mapping
// turns 404, 409 and 503 into Internal.
func (api *member) EmailJoinToQueue(ctx context.Context, in *cc.EmailJoinToQueueRequest) (*cc.EmailJoinToQueueResponse, error) {
	if in.GetPriority() < 0 {
		return nil, status.Error(codes.InvalidArgument, model.EmailJoinInvalidPriority)
	}
	if in.GetDomainId() <= 0 || in.GetThreadId() <= 0 || in.GetQueueId() <= 0 || !emailEventIdRe.MatchString(in.GetEmailEventId()) {
		return nil, status.Error(codes.InvalidArgument, "domain_id, thread_id, queue_id and a UUID email_event_id are required")
	}
	if in.GetStickyAgentId() < 0 {
		return nil, status.Error(codes.InvalidArgument, model.EmailJoinInvalidArguments)
	}

	res, err := api.app.Queue().Manager().EmailJoinToQueue(ctx, model.EmailJoin{
		EventId:         in.GetEmailEventId(),
		DomainId:        in.GetDomainId(),
		ThreadId:        in.GetThreadId(),
		QueueId:         in.GetQueueId(),
		Priority:        in.GetPriority(),
		StickyAgentId:   in.GetStickyAgentId(),
		ExtraEmailCount: in.GetExtraEmailCount(),
		FromAddress:     in.GetFromAddress(),
	})
	if err != nil {
		return nil, emailJoinStatus(ctx, err)
	}

	return &cc.EmailJoinToQueueResponse{
		AttemptId: res.AttemptId,
		QueueId:   res.QueueId,
		Result:    emailJoinResult(res.Result),
	}, nil
}

func emailJoinStatus(ctx context.Context, err *model.AppError) error {
	if ctxErr := ctx.Err(); ctxErr != nil {
		if errors.Is(ctxErr, context.DeadlineExceeded) {
			return status.Error(codes.DeadlineExceeded, ctxErr.Error())
		}
		return status.Error(codes.Canceled, ctxErr.Error())
	}

	code := codes.Internal
	switch err.StatusCode {
	case http.StatusBadRequest:
		code = codes.InvalidArgument
	case http.StatusNotFound:
		code = codes.NotFound
	case http.StatusPreconditionFailed:
		code = codes.FailedPrecondition
	case http.StatusConflict:
		code = codes.AlreadyExists
	case http.StatusServiceUnavailable:
		code = codes.Unavailable
	}

	return status.Error(code, err.Id)
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
