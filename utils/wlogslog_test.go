package utils

import (
	"context"
	"encoding/json"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/webitel/wlog"
)

func TestWlogHandlerEnabledAlwaysTrue(t *testing.T) {
	// wlog exposes no level query, so the handler must not filter.
	log, _ := newSlogTestLogger(t)
	h := NewSlogHandler(log)

	for _, lvl := range []slog.Level{slog.LevelDebug, slog.LevelInfo, slog.LevelWarn, slog.LevelError} {
		if !h.Enabled(context.Background(), lvl) {
			t.Errorf("Enabled(%v) = false, want true", lvl)
		}
	}
}

func TestWlogHandlerWritesThroughToWlog(t *testing.T) {
	log, read := newSlogTestLogger(t)
	slog.New(NewSlogHandler(log)).Info("registry started", "checks", 4)

	out := read()
	if !strings.Contains(out, "registry started") {
		t.Errorf("message missing from wlog output: %s", out)
	}

	if !strings.Contains(out, "checks") {
		t.Errorf("attribute missing from wlog output: %s", out)
	}
}

func TestWlogHandlerLevelMapping(t *testing.T) {
	tests := []struct {
		name  string
		level slog.Level
		want  string
	}{
		{"debug", slog.LevelDebug, "DEBUG"},
		{"info", slog.LevelInfo, "INFO"},
		{"warn", slog.LevelWarn, "WARN"},
		{"error", slog.LevelError, "ERROR"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			log, read := newSlogTestLogger(t)
			slog.New(NewSlogHandler(log)).Log(context.Background(), tt.level, "msg-"+tt.name)

			var rec struct {
				Level string `json:"level"`
			}

			line := strings.TrimSpace(read())
			if line == "" {
				t.Fatal("nothing logged")
			}

			if err := json.Unmarshal([]byte(line), &rec); err != nil {
				t.Fatalf("log line is not JSON: %q", line)
			}

			if rec.Level != tt.want {
				t.Errorf("level = %q, want %q", rec.Level, tt.want)
			}
		})
	}
}

// Handlers must be safe to share, so WithAttrs must copy rather than mutate.
func TestWlogHandlerWithAttrsDoesNotLeak(t *testing.T) {
	log, _ := newSlogTestLogger(t)
	base := NewSlogHandler(log)

	a := base.WithAttrs([]slog.Attr{slog.String("branch", "a")})
	b := base.WithAttrs([]slog.Attr{slog.String("branch", "b")})

	if got := len(base.(*slogHandler).fields); got != 0 {
		t.Errorf("base handler mutated: has %d fields, want 0", got)
	}

	if got := len(a.(*slogHandler).fields); got != 1 {
		t.Errorf("branch a: %d fields, want 1", got)
	}

	if got := len(b.(*slogHandler).fields); got != 1 {
		t.Errorf("branch b: %d fields, want 1", got)
	}

	// A second derivation must not disturb the first.
	a2 := a.WithAttrs([]slog.Attr{slog.String("extra", "x")})
	if got := len(a.(*slogHandler).fields); got != 1 {
		t.Errorf("parent grew to %d fields after deriving a child", got)
	}

	if got := len(a2.(*slogHandler).fields); got != 2 {
		t.Errorf("child: %d fields, want 2", got)
	}
}

func TestWlogHandlerWithGroupAndEmptyCases(t *testing.T) {
	log, _ := newSlogTestLogger(t)
	base := NewSlogHandler(log)

	if got := base.WithAttrs(nil); got != base {
		t.Error("WithAttrs(nil) should return the receiver unchanged")
	}

	if got := base.WithGroup(""); got != base {
		t.Error(`WithGroup("") should return the receiver unchanged`)
	}

	// WithGroup qualifies later keys via a prefix; it emits no field of its own.
	sub := base.WithGroup("sub").(*slogHandler)
	if sub.prefix != "sub." {
		t.Errorf("prefix = %q, want %q", sub.prefix, "sub.")
	}

	if got := len(sub.fields); got != 0 {
		t.Errorf("WithGroup should add no field, got %d", got)
	}
}

func TestAttrLogValuerIsResolved(t *testing.T) {
	log, read := newSlogTestLogger(t)
	slog.New(NewSlogHandler(log)).Info("m", "k", slogResolvable{v: "resolved"})

	if got := slogLine(t, read)["k"]; got != "resolved" {
		t.Errorf("k = %#v, want \"resolved\" — LogValuer was not resolved", got)
	}
}

func TestAttrEmptyAndEmptyGroupAreDropped(t *testing.T) {
	log, read := newSlogTestLogger(t)
	slog.New(NewSlogHandler(log)).Info("m",
		slog.Attr{},
		slog.Group("empty"),
		slog.String("kept", "yes"),
	)

	m := slogLine(t, read)
	if _, ok := m["empty"]; ok {
		t.Error("an empty group was emitted")
	}

	if m["kept"] != "yes" {
		t.Errorf("real attr lost: %#v", m)
	}
}

func TestAttrNamedGroupIsQualified(t *testing.T) {
	log, read := newSlogTestLogger(t)
	slog.New(NewSlogHandler(log)).Info("m", slog.Group("db", slog.String("host", "h")))

	if got := slogLine(t, read)["db.host"]; got != "h" {
		t.Errorf("want db.host=h, got %#v", got)
	}
}

// Only a wholly empty Attr is dropped; an empty key carrying a value is not.
func TestAttrEmptyKeyWithValueIsKept(t *testing.T) {
	log, read := newSlogTestLogger(t)
	slog.New(NewSlogHandler(log)).Info("m", slog.String("", "v"))

	if got := slogLine(t, read)[""]; got != "v" {
		t.Errorf(`want ""="v", got %#v`, got)
	}
}

// A group with an empty key contributes no qualifier.
func TestAttrEmptyKeyGroupIsInlined(t *testing.T) {
	log, read := newSlogTestLogger(t)
	slog.New(NewSlogHandler(log)).Info("m", slog.Group("", slog.String("host", "h")))

	m := slogLine(t, read)
	if got := m["host"]; got != "h" {
		t.Errorf("want host=h inlined, got %#v", m)
	}
}

// Sibling groups must sit beside each other, not nest.
func TestWithGroupSiblingsDoNotNest(t *testing.T) {
	log, read := newSlogTestLogger(t)
	base := slog.New(NewSlogHandler(log))
	base.WithGroup("a").With("x", 1).WithGroup("b").Info("m", "y", 2)

	m := slogLine(t, read)
	if m["a.x"] == nil || m["a.b.y"] == nil {
		t.Errorf("want a.x and a.b.y, got %#v", m)
	}
}

// newSlogTestLogger returns a wlog logger writing JSON to a temp file, plus a reader.
func newSlogTestLogger(t *testing.T) (*wlog.Logger, func() string) {
	t.Helper()

	path := filepath.Join(t.TempDir(), "test.log")
	log := wlog.NewLogger(&wlog.LoggerConfiguration{
		EnableFile:   true,
		FileJson:     true,
		FileLevel:    "debug",
		FileLocation: path,
	})

	return log, func() string {
		b, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("read log: %v", err)
		}

		return string(b)
	}
}

// decode the single JSON line the logger wrote
func slogLine(t *testing.T, read func() string) map[string]any {
	t.Helper()

	line := strings.TrimSpace(read())
	if line == "" {
		t.Fatal("nothing logged")
	}

	var m map[string]any
	if err := json.Unmarshal([]byte(line), &m); err != nil {
		t.Fatalf("not JSON: %q", line)
	}

	return m
}

type slogResolvable struct{ v string }

func (r slogResolvable) LogValue() slog.Value { return slog.StringValue(r.v) }
