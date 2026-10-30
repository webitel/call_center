package model

import (
	"encoding/json"
	"testing"
	"time"
)

func TestEmailSnapshotEventIDIsStablePerOutboxSequence(t *testing.T) {
	first := EmailSnapshotEventId(42)
	if first == "" || first != EmailSnapshotEventId(42) || first == EmailSnapshotEventId(43) {
		t.Fatalf("unstable snapshot ids: %q, %q, %q", first, EmailSnapshotEventId(42), EmailSnapshotEventId(43))
	}
}

func TestEmailSnapshotMarkerKeepsExplicitNullAttemptFields(t *testing.T) {
	row := &EmailOutboxRow{
		Sequence: 42, DomainId: 1, ThreadId: 7, Transition: EmailTransitionInboundReopened,
		Source: "system", OccurredAt: time.Date(2026, 10, 19, 12, 0, 0, 0, time.FixedZone("offset", 2*3600)),
	}
	event := row.Event()
	if event.EventId != EmailSnapshotEventId(42) || event.ProjectionVersion != 42 || event.OccurredAt.Location() != time.UTC {
		t.Fatalf("event envelope: %+v", event)
	}

	data, err := json.Marshal(event)
	if err != nil {
		t.Fatal(err)
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{
		"attempt_id", "attempt_version", "attempt_state", "result", "queue_id", "agent_id", "agent_user_id", "postponed_until",
	} {
		if string(fields[name]) != "null" {
			t.Errorf("%s = %s, want explicit null", name, fields[name])
		}
	}
}
