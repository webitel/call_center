package utils

import (
	"context"
	"log/slog"
	"slices"

	"github.com/webitel/wlog"
)

// slogHandler bridges log/slog to wlog, for libraries that take a *slog.Logger.
type slogHandler struct {
	log    *wlog.Logger
	fields []wlog.Field
	// prefix is the accumulated group path, "" or "a.b.". Dotted keys rather
	// than wlog.Namespace: a zap namespace stays open, so siblings would nest.
	prefix string
}

// NewSlogHandler returns a slog.Handler that writes through to log.
func NewSlogHandler(log *wlog.Logger) slog.Handler {
	return &slogHandler{log: log}
}

// wlog exposes no level query, so filtering is left to wlog.
func (h *slogHandler) Enabled(context.Context, slog.Level) bool {
	return true
}

func (h *slogHandler) Handle(_ context.Context, rec slog.Record) error {
	fields := make([]wlog.Field, 0, len(h.fields)+rec.NumAttrs())
	fields = append(fields, h.fields...)

	rec.Attrs(func(a slog.Attr) bool {
		fields = appendSlogAttr(fields, a, h.prefix)

		return true
	})

	switch {
	case rec.Level >= slog.LevelError:
		h.log.Error(rec.Message, fields...)
	case rec.Level >= slog.LevelWarn:
		h.log.Warn(rec.Message, fields...)
	case rec.Level >= slog.LevelInfo:
		h.log.Info(rec.Message, fields...)
	default:
		h.log.Debug(rec.Message, fields...)
	}

	return nil
}

// Copies rather than mutates: slog handlers must be safe to share.
func (h *slogHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	if len(attrs) == 0 {
		return h
	}

	fields := make([]wlog.Field, len(h.fields), len(h.fields)+len(attrs))
	copy(fields, h.fields)

	for _, a := range attrs {
		fields = appendSlogAttr(fields, a, h.prefix)
	}

	return &slogHandler{log: h.log, fields: fields, prefix: h.prefix}
}

func (h *slogHandler) WithGroup(name string) slog.Handler {
	if name == "" {
		return h
	}

	fieldsCopy := slices.Clone(h.fields)

	return &slogHandler{log: h.log, fields: fieldsCopy, prefix: h.prefix + name + "."}
}

// appendSlogAttr follows the slog contract: resolve LogValuer, drop wholly empty
// attrs and empty groups, inline a group whose key is empty.
func appendSlogAttr(fields []wlog.Field, a slog.Attr, prefix string) []wlog.Field {
	a.Value = a.Value.Resolve()

	if a.Equal(slog.Attr{}) {
		return fields
	}

	if a.Value.Kind() == slog.KindGroup {
		group := a.Value.Group()
		if len(group) == 0 {
			return fields
		}

		if a.Key != "" {
			prefix += a.Key + "."
		}

		for _, ga := range group {
			fields = appendSlogAttr(fields, ga, prefix)
		}

		return fields
	}

	return append(fields, wlog.Any(prefix+a.Key, a.Value.Any()))
}
