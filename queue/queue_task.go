package queue

import (
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
}

type TaskAgentQueueSettings struct {
	MaxTimeSec uint32 `json:"max_time_sec"`
}

//todo max working task ?
type TaskChannel struct {
	id          string
	state       TaskState
	stateC      chan TaskState
	createdAt   int64
	answeredAt  int64
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

func (t *TaskChannel) SetAnswered() *model.AppError {
	t.Lock()
	defer t.Unlock()

	if t.answeredAt != 0 {
		return model.NewAppError("TaskChannel", "queue.task.valid.bridged_at", nil,
			fmt.Sprintf("task %s is bridged", t.id), http.StatusBadRequest)
	}

	t.answeredAt = model.GetMillis()
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
	return t.answeredAt == 0
}

func NewTaskAgentQueue(base BaseQueue) QueueObject {
	return &TaskAgentQueue{
		BaseQueue: base,
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

	go queue.run(team, attempt, attempt.Agent(), task)
	return nil
}

func (queue *TaskAgentQueue) run(team *agentTeam, attempt *Attempt, agent agent_manager.AgentObject, task *TaskChannel) {
	if !queue.queueManager.DoDistributeSchema(&queue.BaseQueue, attempt) {
		queue.queueManager.LeavingMember(attempt, queue)
		return
	}

	timeout := time.NewTimer(time.Second * time.Duration(team.CallTimeout()))
	process := true

	queue.Hook(agent, NewDistributeEvent(attempt, agent.UserId(), queue, agent, team.PostProcessing(), nil, task))

	team.Offering(attempt, agent, task, nil)

	for process {
		select {
		case s := <-task.stateC:
			switch s {
			case TaskStateBridged:
				timeout.Stop()
				team.Answered(attempt, agent)
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

	if task.IsDeclined() {
		team.CancelAgentAttempt(attempt, agent)
	} else {
		team.Reporting(attempt, agent, task.ReportingAt() > 0)
	}

	queue.queueManager.LeavingMember(attempt, queue)
}
