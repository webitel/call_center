package sqlstore

import (
	"fmt"
	"net/http"
	"testing"

	"github.com/lib/pq"
	"github.com/webitel/call_center/model"
)

func TestEmailJoinPriorityErrorMapping(t *testing.T) {
	for _, err := range []error{
		&pq.Error{Code: emailJoinPriorityInvalid},
		fmt.Errorf("wrapped: %w", &pq.Error{Code: emailJoinPriorityInvalid}),
	} {
		id, code := emailJoinError(err)
		if id != model.EmailJoinInvalidPriority || code != http.StatusBadRequest {
			t.Fatalf("unexpected mapping: %s %d", id, code)
		}
	}
}

func TestEmailJoinInvalidArgumentsErrorMapping(t *testing.T) {
	for _, sqlstate := range []pq.ErrorCode{"22023", "22P02"} {
		id, code := emailJoinError(&pq.Error{Code: sqlstate})
		if id != model.EmailJoinInvalidArguments || code != http.StatusBadRequest {
			t.Fatalf("SQLSTATE %s: unexpected mapping: %s %d", sqlstate, id, code)
		}
	}
}
