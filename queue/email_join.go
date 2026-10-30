package queue

import (
	"context"

	"github.com/webitel/wlog"

	"github.com/webitel/call_center/model"
)

// EmailJoinToQueue puts an email-service Thread into an Inbound Email Queue. The
// store validates the queue in its transaction, so the queue cache is not used.
func (qm *Manager) EmailJoinToQueue(ctx context.Context, in model.EmailJoin) (*model.EmailJoinResult, *model.AppError) {
	log := qm.log.With(
		wlog.String("email_event_id", in.EventId),
		wlog.Int64("domain_id", in.DomainId),
		wlog.Int64("email_thread_id", in.ThreadId),
		wlog.Int("requested_queue_id", int(in.QueueId)),
	)

	res, err := qm.store.Member().EmailJoinToQueue(ctx, in, qm.app.QueueSettings().EmailCommandLockTimeout)
	if err != nil {
		log.Error("email join failed", wlog.Err(err), wlog.String("error_id", err.Id))
		return nil, err
	}

	log = log.With(
		wlog.Int("queue_id", int(res.QueueId)),
		wlog.Int64("attempt_id", res.AttemptId),
		wlog.String("result", res.Result),
	)
	if res.Result == model.EmailJoinReplayed && res.RequestedQueueId != in.QueueId {
		log.Warn("email join replayed with another queue; the first queue is kept",
			wlog.Int("first_requested_queue_id", int(res.RequestedQueueId)))
	} else {
		log.Info("email joined to queue")
	}

	return res, nil
}
