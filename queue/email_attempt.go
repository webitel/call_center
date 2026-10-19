package queue

import (
	"context"

	"github.com/webitel/wlog"

	"github.com/webitel/call_center/model"
)

// EmailAttemptCommand changes an Email attempt in the database; Email attempts never enter the
// attempt cache of this node, so any node serves the command.
func (qm *Manager) EmailAttemptCommand(ctx context.Context, cmd model.EmailAttemptCommand) (*model.EmailAttemptResult, *model.AppError) {
	log := qm.log.With(
		wlog.String("operation", cmd.Op),
		wlog.String("source", cmd.Source),
		wlog.String("command_id", cmd.CommandId),
		wlog.Int64("domain_id", cmd.DomainId),
		wlog.Int64("email_thread_id", cmd.ThreadId),
	)

	res, err := qm.store.Member().EmailAttemptCommand(ctx, cmd, qm.app.QueueSettings().EmailCommandLockTimeout)
	if err != nil {
		log.Warn("email attempt command failed", wlog.String("error_id", err.Id), wlog.Err(err))
		return nil, err
	}

	log.Info("email attempt command",
		wlog.Int64("attempt_id", res.AttemptId),
		wlog.String("state", res.State),
		wlog.Int64("attempt_version", res.AttemptVersion),
		wlog.Int64("projection_version", res.ProjectionVersion),
		wlog.Any("replayed", res.Replayed),
	)

	return res, nil
}

// EmailWakeUp wakes the active attempt of a Thread once per inbound Email event.
func (qm *Manager) EmailWakeUp(ctx context.Context, in model.EmailWakeUp) (*model.EmailWakeUpResult, *model.AppError) {
	log := qm.log.With(
		wlog.String("email_event_id", in.EventId),
		wlog.Int64("domain_id", in.DomainId),
		wlog.Int64("email_thread_id", in.ThreadId),
	)

	res, err := qm.store.Member().EmailWakeUp(ctx, in, qm.app.QueueSettings().EmailCommandLockTimeout)
	if err != nil {
		log.Warn("email wake-up failed", wlog.String("error_id", err.Id), wlog.Err(err))
		return nil, err
	}

	fields := []wlog.Field{wlog.String("result", res.Result), wlog.Any("replayed", res.Replayed)}
	if res.AttemptId != nil {
		fields = append(fields, wlog.Int64("attempt_id", *res.AttemptId))
	}
	if res.FallbackQueueId != nil {
		fields = append(fields, wlog.Int("fallback_queue_id", int(*res.FallbackQueueId)))
	}
	if res.Result == model.EmailWakeupNoop || res.Result == model.EmailWakeupNotActive {
		log.Debug("email wake-up", fields...)
	} else {
		log.Info("email wake-up", fields...)
	}

	return res, nil
}
