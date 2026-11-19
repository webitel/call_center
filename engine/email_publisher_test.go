package engine

import (
	"testing"
	"time"
)

func TestEmailPublisherSettingsCommandRetention(t *testing.T) {
	s := EmailPublisherSettings{Interval: time.Second, Batch: 1, Lease: 30 * time.Second, ConfirmTimeout: time.Second,
		Retention: time.Hour, CommandRetention: 24 * time.Hour}
	if err := s.Validate(); err != nil {
		t.Fatalf("valid settings: %v", err)
	}
	s.CommandRetention = 23 * time.Hour
	if s.Validate() == nil {
		t.Error("command retention below 24h was accepted")
	}
}
