package app

import (
	"encoding/json"
	"fmt"
	"net/http"

	"golang.org/x/sync/singleflight"

	"github.com/webitel/wlog"

	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/utils"
)

var (
	queueGroup          singleflight.Group
	recordAllCallsCache = utils.NewLruWithParams(1000, "RecordAllCalls", 60, "")
)

func (a *App) GetQueueById(id int64) (*model.Queue, *model.AppError) {
	return a.Store.Queue().GetById(id)
}

func (a *App) RecordAllCalls(domainID int64) bool {
	if v, ok := recordAllCallsCache.Get(domainID); ok {
		if res, valid := v.(bool); valid {
			return res
		}
	}

	v, err, _ := queueGroup.Do(recordAllCallsKey(domainID), func() (any, error) {
		res, err := a.Store.Queue().RecordAllCalls(domainID)
		if err != nil {
			return nil, err
		}

		return res, nil
	})
	if err != nil {
		a.Log.Error(err.Error(),
			wlog.Err(err),
			wlog.Int64("domain_id", domainID),
		)

		return false
	}

	res, valid := v.(bool)
	if !valid {
		return false
	}

	recordAllCallsCache.AddWithDefaultExpires(domainID, res)

	return res
}

func (a *App) listenSystemSettingEvents(events <-chan model.SystemSettingEvent) {
	for e := range events {
		if e.Name != model.SysNameRecordAllCalls {
			continue
		}

		recordAllCallsCache.Remove(e.DomainID)
		queueGroup.Forget(recordAllCallsKey(e.DomainID))
	}
}

func recordAllCallsKey(domainID int64) string {
	return fmt.Sprintf("record-all-calls-%d", domainID)
}

func (a *App) queueUserIds(queueId, skipAgentId int) (model.Int64Array, *model.AppError) {
	ids, err, _ := queueGroup.Do(fmt.Sprintf("queue-%d", queueId), func() (any, error) {
		ids, err := a.Store.Queue().UserIds(queueId, skipAgentId)
		if err != nil {
			return nil, err
		}

		return ids, nil
	})

	if err != nil {
		switch err.(type) {
		case *model.AppError:
			return nil, err.(*model.AppError)
		default:
			return nil, model.NewAppError("GetQueueAgents", "app.queue.get_agents.app_err", nil, err.Error(), http.StatusInternalServerError)

		}
	}

	if ids == nil {
		return nil, nil
	}

	return ids.(model.Int64Array), nil
}

func (a *App) NotificationHideMember(domainId int64, queueId int, memberId *int64, skipAgentId int) *model.AppError {
	if memberId == nil {
		return nil
	}

	ids, err := a.queueUserIds(queueId, skipAgentId)
	if err != nil {
		return err
	}

	if ids == nil {
		return nil
	}

	return a.MQ.SendNotification(domainId, &model.Notification{
		Id:        0,
		DomainId:  domainId,
		Action:    model.NotificationHideMember,
		CreatedAt: model.GetMillis(),
		ForUsers:  ids,
		Body: map[string]any{
			"member_id": *memberId,
		},
	})
}

func (a *App) NotificationInterceptAttempt(domainId int64, queueId int, channel string, attemptId int64, skipAgentId int32) *model.AppError {
	if attemptId == 0 {
		return nil
	}

	ids, err := a.queueUserIds(queueId, int(0))
	if err != nil {
		return err
	}

	if ids == nil {
		return nil
	}

	return a.MQ.SendNotification(domainId, &model.Notification{
		Id:        0,
		DomainId:  domainId,
		Action:    model.NotificationHideAttempt,
		CreatedAt: model.GetMillis(),
		ForUsers:  ids,
		Body: map[string]any{
			"attempt_id": attemptId,
			"channel":    channel,
		},
	})
}

func (a *App) NotificationWaitingList(e *model.MemberWaitingByUsers) *model.AppError {
	return a.MQ.SendNotification(e.DomainId, &model.Notification{
		Id:        0,
		DomainId:  e.DomainId,
		Action:    model.NotificationWaitingList,
		CreatedAt: model.GetMillis(),
		ForUsers:  e.Users,
		Body: map[string]any{
			"calls": e.Calls,
			"chats": e.Chats,
		},
	})
}

func (a *App) NotificationQueue(payload map[string]any) *model.AppError {
	data, _ := json.Marshal(payload)
	return a.MQ.SendJSON("queue", data)
}
