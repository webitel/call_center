package model

import (
	"net/http"
	"testing"
)

func TestEmailJoinRejectsInvalidPriority(t *testing.T) {
	j := EmailJoin{EventId: "00000000-0000-4000-8000-000000000001", DomainId: 1, ThreadId: 2, QueueId: 3, Priority: -1}
	if err := j.IsValid(); err == nil || err.Id != EmailJoinInvalidPriority || err.StatusCode != http.StatusBadRequest {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestEmailJoinRejectsNegativeStickyAgent(t *testing.T) {
	j := EmailJoin{EventId: "00000000-0000-4000-8000-000000000001", DomainId: 1, ThreadId: 2, QueueId: 3, StickyAgentId: -1}
	if err := j.IsValid(); err == nil || err.Id != EmailJoinInvalidArguments || err.StatusCode != http.StatusBadRequest {
		t.Fatalf("unexpected error: %v", err)
	}
}
