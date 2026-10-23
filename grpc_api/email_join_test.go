package grpc_api

import (
	"context"
	"fmt"
	"net/http"
	"testing"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/webitel/call_center/gen/cc"
	"github.com/webitel/call_center/model"
)

func TestEmailJoinRejectsInvalidPriorityBeforeApp(t *testing.T) {
	for _, priority := range []int32{-1, 101} {
		t.Run(fmt.Sprint(priority), func(t *testing.T) {
			var api *member
			_, err := api.EmailJoinToQueue(context.Background(), &cc.EmailJoinToQueueRequest{
				DomainId: 1, ThreadId: 2, QueueId: 3,
				EmailEventId: "00000000-0000-4000-8000-000000000001", Priority: priority,
			})
			if status.Code(err) != codes.InvalidArgument || status.Convert(err).Message() != model.EmailJoinInvalidPriority {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}

func TestEmailJoinRejectsNegativeStickyAgent(t *testing.T) {
	var api *member
	_, err := api.EmailJoinToQueue(context.Background(), &cc.EmailJoinToQueueRequest{
		DomainId: 1, ThreadId: 2, QueueId: 3,
		EmailEventId: "00000000-0000-4000-8000-000000000001", StickyAgentId: -1,
	})
	if status.Code(err) != codes.InvalidArgument || status.Convert(err).Message() != model.EmailJoinInvalidArguments {
		t.Fatalf("unexpected error: %v", err)
	}
}

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
