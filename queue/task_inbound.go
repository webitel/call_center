package queue

import (
	"encoding/json"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/model"
	"strconv"
	"time"
)

type TaskInboundQueue struct {
	BaseQueue
	TaskInboundQueueSettings
}

type TaskInboundQueueSettings struct {
	MaxAttempts            uint   `json:"max_attempts"`
	PerNumbers             bool   `json:"per_numbers"`
	WaitBetweenRetries     uint64 `json:"wait_between_retries"`
	WaitBetweenRetriesDesc bool   `json:"wait_between_retries_desc"`
}

func TaskInboundSettingsFromBytes(data []byte) TaskInboundQueueSettings {
	var settings TaskInboundQueueSettings
	json.Unmarshal(data, &settings)
	return settings
}

func NewTaskInboundQueue(base BaseQueue, settings TaskInboundQueueSettings) QueueObject {
	return &TaskInboundQueue{
		BaseQueue:                base,
		TaskInboundQueueSettings: settings,
	}
}

func (queue *TaskInboundQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
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

func (queue *TaskInboundQueue) run(team *agentTeam, attempt *Attempt, agent agent_manager.AgentObject, task *TaskChannel) {
	if !queue.queueManager.DoDistributeSchema(&queue.BaseQueue, attempt) {
		queue.queueManager.LeavingMember(attempt)
		return
	}

	timeout := time.NewTimer(time.Second * time.Duration(team.TaskAcceptTimeout()))
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
