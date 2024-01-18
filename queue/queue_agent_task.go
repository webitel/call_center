package queue

import (
	"encoding/json"
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/model"
	"net/http"
	"strconv"
	"sync"
	"time"
)

type TaskState uint8

const (
	TaskStateIdle TaskState = iota
	TaskStateBridged
	TaskStateClosed
)

type TaskAgentQueue struct {
	BaseQueue
	TaskAgentQueueSettings
}

type TaskAgentQueueSettings struct {
	MaxAttempts            uint   `json:"max_attempts"`
	PerNumbers             bool   `json:"per_numbers"`
	WaitBetweenRetries     uint64 `json:"wait_between_retries"`
	WaitBetweenRetriesDesc bool   `json:"wait_between_retries_desc"`
}

// todo max working task ?
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

func TaskAgentSettingsFromBytes(data []byte) TaskAgentQueueSettings {
	var settings TaskAgentQueueSettings
	json.Unmarshal(data, &settings)
	return settings
}

func NewTaskAgentQueue(base BaseQueue, settings TaskAgentQueueSettings) QueueObject {
	return &TaskAgentQueue{
		BaseQueue:              base,
		TaskAgentQueueSettings: settings,
	}
}

func (queue *TaskAgentQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	if attempt.agent == nil {
		return NewErrorAgentRequired(queue, attempt)
	}

	team, err := queue.GetTeam(attempt)
	if err != nil {
		return err
	}

	task := NewTaskChannel(strconv.Itoa(int(attempt.Id())))
	attempt.channelData = task

	attempt.waitBetween = queue.WaitBetweenRetries
	attempt.maxAttempts = queue.MaxAttempts
	attempt.perNumbers = queue.PerNumbers

	go queue.run(team, attempt, attempt.Agent(), task)
	return nil
}

func (queue *TaskAgentQueue) run(team *agentTeam, attempt *Attempt, agent agent_manager.AgentObject, task *TaskChannel) {
	if !queue.queueManager.DoDistributeSchema(&queue.BaseQueue, attempt) {
		queue.queueManager.LeavingMember(attempt)
		return
	}

	timeout := time.NewTimer(time.Second * time.Duration(team.CallTimeout()))
	process := true

	team.Distribute(queue, agent, NewDistributeEvent(attempt, agent.UserId(), queue, agent, queue.Processing(), nil, task))
	team.Offering(attempt, agent, task, nil)

	for process {
		select {
		case s := <-task.stateC:
			switch s {
			case TaskStateBridged:
				timeout.Stop()
				team.Bridged(attempt, agent)
			case TaskStateClosed:
				timeout.Stop()
				process = false
			}
		case <-timeout.C:
			attempt.Log("timeout")
			process = false
			break
		}
	}

	if task.IsDeclined() && task.ReportingAt() == 0 {
		team.CancelAgentAttempt(attempt, agent)
		queue.queueManager.LeavingMember(attempt)
	} else {
		team.Reporting(queue, attempt, agent, task.ReportingAt() > 0, false)
	}
}

func (t *TaskChannel) Stats() map[string]string {
	// todo
	return map[string]string{}
}
