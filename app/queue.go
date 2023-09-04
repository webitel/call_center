package app

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"golang.org/x/sync/singleflight"
	"net/http"
)

var (
	queueGroup singleflight.Group
)

func (a *App) GetQueueById(id int64) (*model.Queue, *model.AppError) {
	return a.Store.Queue().GetById(id)
}

func (a *App) queueUserIds(queueId int, skipAgentId int) (model.Int64Array, *model.AppError) {
	ids, err, _ := queueGroup.Do(fmt.Sprintf("queue-%d", queueId), func() (interface{}, error) {
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
		Body: map[string]interface{}{
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
		Body: map[string]interface{}{
			"attempt_id": attemptId,
			"channel":    channel,
		},
	})
}

func (a *App) NotificationWaitingList(domainId int64, userIds []int64, list []*model.MemberWaiting) *model.AppError {
	return a.MQ.SendNotification(domainId, &model.Notification{
		Id:        0,
		DomainId:  domainId,
		Action:    model.NotificationWaitingList,
		CreatedAt: model.GetMillis(),
		ForUsers:  userIds,
		Body: map[string]interface{}{
			"list": list,
		},
	})
}
