package dialing

import (
	"fmt"
	"github.com/webitel/call_center/model"
)

type Queue struct {
	id        int
	updatedAt int64
	name      string
}

func NewQueue(settings *model.Queue) *Queue {
	return &Queue{
		id:        settings.Id,
		updatedAt: settings.UpdatedAt,
	}
}

func (queue *Queue) IsExpire(updatedAt int64) bool {
	return queue.updatedAt != updatedAt
}

func (queue *Queue) Name() string {
	return fmt.Sprintf("%v", queue.id)
}
