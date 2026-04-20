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

type IMMemberInfo struct {
	Name  string `json:"name"`
	Sub   string `json:"chat"` // todo
	ToSub string `json:"to_sub"`
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
	var imInfo IMMemberInfo

	if attempt.member == nil {
		return NewErrorVariableRequired(queue, attempt, "member")
	}
	_ = json.Unmarshal(attempt.member.Destination, &imInfo)

	sess := queue.queueManager.NewIMSession(attempt, imInfo.ToSub)
	go queue.run(attempt, sess, imInfo)

	return nil
}

func (queue *InboundIMQueue) run(attempt *Attempt, sess *im.Session, imInfo IMMemberInfo) {
	var err *model.AppError
	var team *agentTeam
	var task *TaskChannel
	var agent agent_manager.AgentObject
	var inviteTimeout *time.Timer
	var timeoutStrategy bool

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
			loop = false

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

			task = NewTaskChannel(strconv.Itoa(int(attempt.Id())))
			attempt.channelData = task

			inviteTimeout = time.NewTimer(time.Second * time.Duration(team.InviteChatTimeout()))
			process := true

			team.Distribute(queue, agent, NewDistributeEvent(attempt, agent.UserId(), queue, agent, queue.Processing(), sess, task))
			team.Offering(attempt, agent, task, sess)

			for process {
				select {
				case s := <-task.stateC:
					inviteTimeout.Stop()

					switch s {
					case TaskStateBridged:

						err2 := sess.AddMemberUser(attempt.Context, agent.UserId())
						if err2 != nil {
							// TODO clean invite
							attempt.Log(err2.Error())
						}
						// TODO
						queue.queueManager.NotificationQueue(model.MemberStateBridged, attempt)
						attempt.Log("bridged")
						timeout.Reset(time.Second * time.Duration(timerCheckIdle))
						sess.SetActivity()
						team.Bridged(attempt, agent)

					case TaskStateClosed:

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
			if attempt.bridgedAt > 0 {
				// wlog.Debug(fmt.Sprintf("attempt [%d] agent_idle=%d member_idle=%d dialog=%d", attempt.Id(), aSess.IdleSec(), mSess.IdleSec(), conv.SilentSec()))

				if queue.settings.LastMessageTimeout {
					timeoutStrategy = task != nil && sess.SilentSec() >= queue.settings.MaxIdleAgent && sess.OperatorIdleMessage() > sess.MemberIdleMessage()
				} else {
					timeoutStrategy = task != nil && sess.OperatorIdleMessage() >= queue.settings.MaxIdleAgent
				}

				if queue.settings.MaxIdleAgent > 0 && timeoutStrategy {
					attempt.Log("max idle agent")
					attempt.SetResult(AttemptResultAgentTimeout)
					loop = false
					// aSess.Leave(model.AgentTimeout)
					break
				}

				if queue.settings.LastMessageTimeout {
					timeoutStrategy = task != nil && sess.SilentSec() >= queue.settings.MaxIdleClient &&
						sess.MemberIdleMessage() > sess.OperatorIdleMessage()
				} else {
					timeoutStrategy = task != nil && sess.MemberIdleMessage() >= queue.settings.MaxIdleClient
				}

				if queue.settings.MaxIdleClient > 0 && timeoutStrategy {
					attempt.Log("max idle client")
					attempt.SetResult(AttemptResultClientTimeout)
					loop = false
					// aSess.Leave(model.ClientTimeout)
					break
				}

				if queue.settings.MaxIdleDialog > 0 && task != nil && sess.SilentSec() >= queue.settings.MaxIdleDialog {
					attempt.Log("max idle dialog")
					attempt.SetResult(AttemptResultDialogTimeout)
					loop = false
					// aSess.Leave(model.SilenceTimeout)
					break
				}

				timeout.Reset(time.Second * time.Duration(timerCheckIdle))
			} else {
				attempt.Log("timeout")
				loop = false

				break
			}
		}
	}

	if inviteTimeout != nil {
		inviteTimeout.Stop()
	}

	timeout.Stop()

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
		sess.Close()
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
