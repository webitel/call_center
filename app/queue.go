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

func (a *App) NotificationHideMember(domainId int64, queueId int, memberId *int64, skipAgentId int) *model.AppError {
	if memberId == nil {
		return nil
	}

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
			return err.(*model.AppError)
		default:
			return model.NewAppError("GetQueueAgents", "app.queue.get_agents.app_err", nil, err.Error(), http.StatusInternalServerError)

		}
	}

	if ids == nil {
		return nil
	}

	return a.MQ.SendNotification(domainId, &model.Notification{
		Id:        0,
		DomainId:  domainId,
		Action:    model.NotificationHideMember,
		CreatedAt: model.GetMillis(),
		ForUsers:  ids.(model.Int64Array),
		Body: map[string]interface{}{
			"member_id": *memberId,
		},
	})
}
