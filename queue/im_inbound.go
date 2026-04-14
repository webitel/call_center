package queue

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"time"

	"github.com/webitel/wlog"

	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/im"
	"github.com/webitel/call_center/model"
)

type InboundIMQueueSettings struct {
	MaxIdleClient      int64  `json:"max_idle_client"`
	MaxIdleAgent       int64  `json:"max_idle_agent"`
	MaxIdleDialog      int64  `json:"max_idle_dialog"`
	MaxWaitTime        uint32 `json:"max_wait_time"`
	ManualDistribution bool   `json:"manual_distribution"`
	LastMessageTimeout bool   `json:"last_message_timeout"`
}

type InboundIMQueue struct {
	BaseQueue
	settings InboundIMQueueSettings
}

func InboundIMQueueFromBytes(data []byte) InboundIMQueueSettings {
	var settings InboundIMQueueSettings
	json.Unmarshal(data, &settings)
	return settings
}

func NewInboundIMQueue(base BaseQueue, settings InboundIMQueueSettings) QueueObject {
	if settings.MaxWaitTime == 0 {
		settings.MaxWaitTime = 300
	}

	return &InboundIMQueue{
		BaseQueue: base,
		settings:  settings,
	}
}

func (queue *InboundIMQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	sess := queue.queueManager.NewIMSession(attempt, "2522")
	go queue.run(attempt, sess)
	return nil
}

func (queue *InboundIMQueue) run(attempt *Attempt, sess *im.Session) {
	var err *model.AppError
	var team *agentTeam
	var task *TaskChannel
	var agent agent_manager.AgentObject

	defer attempt.Log("stopped queue")

	queue.Hook(HookJoined, attempt)

	attempt.Log("wait agent")

	if err = queue.queueManager.SetFindAgentState(attempt.Id()); err != nil {
		// FIXME
		panic(err.Error())
	}

	attempt.SetState(model.MemberStateWaitAgent)
	ags := attempt.On(AttemptHookDistributeAgent)
	attempt.memberChannel = sess

	timeSec := queue.settings.MaxWaitTime
	timeout := time.NewTimer(time.Second * time.Duration(timeSec))

	loop := true

	for loop {
		select {
		case <-attempt.Cancel():
			// conv.SetStop()
			loop = false
			break
		case <-attempt.Context.Done():
			// conv.SetStop()

		case <-ags:
			agent = attempt.Agent()
			team, err = queue.GetTeam(attempt)
			if err != nil {
				attempt.log.Error(err.Error(),
					wlog.Err(err),
				)

				return
			}

			attempt.Log(fmt.Sprintf("distribute agent %s [%d]", agent.Name(), agent.Id()))

			vars := model.UnionStringMaps(
				attempt.ExportVariables(),
				queue.variables,
				map[string]string{
					model.QUEUE_AGENT_ID_FIELD:   fmt.Sprintf("%d", agent.Id()),
					model.QUEUE_TEAM_ID_FIELD:    fmt.Sprintf("%d", team.Id()),
					model.QUEUE_ID_FIELD:         fmt.Sprintf("%d", queue.Id()),
					model.QUEUE_NAME_FIELD:       queue.Name(),
					model.QUEUE_TYPE_NAME_FIELD:  queue.TypeName(),
					model.QUEUE_ATTEMPT_ID_FIELD: fmt.Sprintf("%d", attempt.Id()),
					"cc_reporting":               fmt.Sprintf("%v", queue.Processing()),
				},
			)

			if queue.settings.ManualDistribution {
				vars[model.QueueAutoAnswerVariable] = "true"
				vars[model.QueueManualDistribute] = "true"
			}

			task = NewTaskChannel(strconv.Itoa(int(attempt.Id())))
			attempt.channelData = task

			inviteTimeout := time.NewTimer(time.Second * time.Duration(team.InviteChatTimeout()))
			process := true

			team.Distribute(queue, agent, NewDistributeEvent(attempt, agent.UserId(), queue, agent, queue.Processing(), sess, task))
			team.Offering(attempt, agent, task, sess)

			for process {
				select {
				case s := <-task.stateC:
					switch s {
					case TaskStateBridged:
						inviteTimeout.Stop()
						err2 := sess.AddMemberUser(attempt.Context, agent.UserId())
						if err2 != nil {
							// TODO clean invite
							attempt.Log(err2.Error())
						}
						// TODO
						queue.queueManager.NotificationQueue(model.MemberStateBridged, attempt)
						team.Bridged(attempt, agent)
					case TaskStateClosed:
						inviteTimeout.Stop()

						if task.IsDeclined() {
							attempt.Log(fmt.Sprintf("conversation decline %s", "TODO"))
							team.MissedAgentAndWaitingAttempt(attempt, agent)
							attempt.SetState(model.MemberStateWaitAgent)

							attempt.Emit(AttemptHookMissedAgent, agent.Id())
							agent = nil
							task = nil
						} else {
							loop = false
						}

						process = false
					}

				case <-inviteTimeout.C:
					handleTimeout(attempt, task, &process)
				case <-timeout.C:
					handleTimeout(attempt, task, &process)
				}
			}

		case <-timeout.C:
			if 0 > 0 {
				timeout.Reset(time.Second * time.Duration(timerCheckIdle))
			} else {
				attempt.Log("timeout")
				// conv.SetStop()
				break
			}
		}
	}

	if agent != nil && team != nil {
		if task.IsDeclined() && task.ReportingAt() == 0 {
			team.Missed(attempt, agent)
			queue.queueManager.LeavingMember(attempt)
		} else {
			team.Reporting(queue, attempt, agent, task.ReportingAt() > 0, false)
		}
	} else {
		queue.queueManager.Abandoned(attempt)
	}

	go func() {
		attempt.Emit(AttemptHookLeaving)
		attempt.Off("*")
		if agent != nil {
			err2 := sess.RemoveMemberUser(context.Background(), agent.UserId(), "leaving")
			if err2 != nil {
				attempt.Log(fmt.Sprintf("remove agent [%d], err = %s", agent.Id(), err2.Error()))
			}
		}
		// TODO
		queue.queueManager.NotificationQueue(model.MemberStateLeaving, attempt)
	}()
}

func handleTimeout(attempt *Attempt, task *TaskChannel, process *bool) {
	attempt.Log("timeout")
	if task != nil && task.bridgedAt == 0 {
		task.SetClosed()
	} else {
		*process = false
	}
}
