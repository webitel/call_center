package sqlstore

import (
	"context"
	"database/sql/driver"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"

	"github.com/lib/pq"

	"github.com/webitel/call_center/model"
)

// SQLSTATE codes raised by cc_email_join_to_queue.
const (
	emailJoinQueueNotFound     = pq.ErrorCode("EMQNF")
	emailJoinQueuePrecondition = pq.ErrorCode("EMQFP")
	emailJoinEventConflict     = pq.ErrorCode("EMKEY")
	emailJoinPriorityInvalid   = pq.ErrorCode("EMPRI")
)

func (s *SqlMemberStore) EmailJoinToQueue(ctx context.Context, in model.EmailJoin) (*model.EmailJoinResult, *model.AppError) {
	if in.Priority < 0 || in.Priority > 100 {
		return nil, model.NewAppError("SqlMemberStore.EmailJoinToQueue", model.EmailJoinInvalidPriority, nil,
			"Email priority must be between 0 and 100", http.StatusBadRequest)
	}
	var res model.EmailJoinResult

	err := s.GetMaster().WithContext(ctx).SelectOne(&res, `select x.join_result, x.join_attempt_id, x.join_queue_id, x.join_requested_queue_id
from call_center.cc_email_join_to_queue(:EventId::uuid, :DomainId::int8, :ThreadId::int8, :QueueId::int4,
    :Priority::int4, :StickyAgentId::int4, :ExtraEmailCount::bool, :FromAddress::text) x`,
		map[string]any{
			"EventId":         in.EventId,
			"DomainId":        in.DomainId,
			"ThreadId":        in.ThreadId,
			"QueueId":         in.QueueId,
			"Priority":        in.Priority,
			"StickyAgentId":   in.StickyAgentId,
			"ExtraEmailCount": in.ExtraEmailCount,
			"FromAddress":     in.FromAddress,
		})
	if err != nil {
		id, code := emailJoinError(err)
		return nil, model.NewAppError("SqlMemberStore.EmailJoinToQueue", id, nil,
			fmt.Sprintf("EventId=%s, DomainId=%d, ThreadId=%d, QueueId=%d: %s", in.EventId, in.DomainId, in.ThreadId, in.QueueId, err.Error()),
			code)
	}

	return &res, nil
}

// emailJoinError gives a stable error id and HTTP status; 503 marks errors worth retrying.
func emailJoinError(err error) (string, int) {
	const prefix = "store.sql_member.email_join."

	var pqErr *pq.Error
	if errors.As(err, &pqErr) {
		switch {
		case pqErr.Code == emailJoinPriorityInvalid:
			return model.EmailJoinInvalidPriority, http.StatusBadRequest
		case pqErr.Code == emailJoinQueueNotFound:
			return prefix + "queue_not_found", http.StatusNotFound
		case pqErr.Code == emailJoinQueuePrecondition:
			return prefix + "queue_precondition", http.StatusPreconditionFailed
		case pqErr.Code == emailJoinEventConflict:
			return prefix + "event_conflict", http.StatusConflict
		case pqErr.Code == "22023" || pqErr.Code == "22P02":
			return model.EmailJoinInvalidArguments, http.StatusBadRequest
		case pqErr.Code == "40001" || pqErr.Code == "40P01" || pqErr.Code == "53300" ||
			pqErr.Code.Class() == "08" || pqErr.Code == "57P01" || pqErr.Code == "57P02" || pqErr.Code == "57P03":
			return prefix + "unavailable", http.StatusServiceUnavailable
		}

		return prefix + "app_error", http.StatusInternalServerError
	}

	var netErr net.Error
	if errors.Is(err, driver.ErrBadConn) || errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF) ||
		errors.As(err, &netErr) || errors.Is(err, context.DeadlineExceeded) || errors.Is(err, context.Canceled) {
		return prefix + "unavailable", http.StatusServiceUnavailable
	}

	return prefix + "app_error", http.StatusInternalServerError
}
