package grpc_api

import (
	"context"
	"net/http"
	"testing"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/webitel/call_center/model"
)

func TestEmailJoinStatus(t *testing.T) {
	cases := map[int]codes.Code{
		http.StatusBadRequest:          codes.InvalidArgument,
		http.StatusNotFound:            codes.NotFound,
		http.StatusPreconditionFailed:  codes.FailedPrecondition,
		http.StatusConflict:            codes.AlreadyExists,
		http.StatusServiceUnavailable:  codes.Unavailable,
		http.StatusInternalServerError: codes.Internal,
	}
	for httpCode, want := range cases {
		err := emailJoinStatus(context.Background(), model.NewAppError("t", "t.id", nil, "", httpCode))
		if got := status.Code(err); got != want {
			t.Errorf("http %d: got %s, want %s", httpCode, got, want)
		}
	}

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	err := emailJoinStatus(ctx, model.NewAppError("t", "t.id", nil, "", http.StatusServiceUnavailable))
	if got := status.Code(err); got != codes.Canceled {
		t.Errorf("canceled context: got %s", got)
	}
}
