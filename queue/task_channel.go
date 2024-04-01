package queue

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"net/http"
	"sync"
)

type TaskState uint8

type TaskChannel struct {
	id          string
	state       TaskState
	stateC      chan TaskState
	createdAt   int64
	bridgedAt   int64
	closedAt    int64
	reportingAt int64
	sync.RWMutex
}

func NewTaskChannel(id string) *TaskChannel {
	return &TaskChannel{
		id:        id,
		createdAt: model.GetMillis(),
		state:     TaskStateIdle,
		stateC:    make(chan TaskState),
	}
}

func (t *TaskChannel) Id() string {
	return t.id
}

func (t *TaskChannel) ReportingAt() int64 {
	t.RLock()
	defer t.RUnlock()

	return t.reportingAt
}

func (t *TaskChannel) setState(state TaskState) {
	t.state = state
	t.stateC <- t.state
}

func (t *TaskChannel) Answered() bool {
	t.RLock()
	a := t.bridgedAt
	t.RUnlock()
	return a > 0
}

func (t *TaskChannel) SetAnswered() *model.AppError {
	t.Lock()
	defer t.Unlock()

	if t.bridgedAt != 0 {
		return model.NewAppError("TaskChannel", "queue.task.valid.bridged_at", nil,
			fmt.Sprintf("task %s is bridged", t.id), http.StatusBadRequest)
	}

	t.bridgedAt = model.GetMillis()
	t.setState(TaskStateBridged)
	return nil
}

func (t *TaskChannel) SetClosed() *model.AppError {
	t.Lock()
	defer t.Unlock()

	if t.closedAt != 0 {
		return model.NewAppError("TaskChannel", "queue.task.valid.closed_at", nil,
			fmt.Sprintf("task %s is closed", t.id), http.StatusBadRequest)
	}

	t.closedAt = model.GetMillis()
	t.setState(TaskStateClosed)
	return nil
}

func (t *TaskChannel) Reporting() *model.AppError {
	t.Lock()
	t.reportingAt = model.GetMillis()
	t.Unlock()

	if t.closedAt == 0 {
		return t.SetClosed()
	}

	return nil
}

func (t *TaskChannel) IsDeclined() bool {
	t.RLock()
	defer t.RUnlock()
	return t.bridgedAt == 0
}

func (t *TaskChannel) Stats() map[string]string {
	// todo
	return map[string]string{}
}
