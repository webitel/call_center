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

const (
	// defaultMaxWaitTime is the default maximum wait time for an attempt in seconds
	defaultMaxWaitTime = 300

	// imTimerCheckIdle is the interval for checking idle timeouts in seconds
	imTimerCheckIdle = 30
)

// InboundIMQueueSettings contains configuration for inbound instant messaging queue
type InboundIMQueueSettings struct {
	MaxIdleClient      int64  `json:"max_idle_client"`      // Maximum client idle time in seconds
	MaxIdleAgent       int64  `json:"max_idle_agent"`       // Maximum agent idle time in seconds
	MaxIdleDialog      int64  `json:"max_idle_dialog"`      // Maximum dialog idle time in seconds
	MaxWaitTime        uint32 `json:"max_wait_time"`        // Maximum wait time for agent in seconds
	ManualDistribution bool   `json:"manual_distribution"`  // Enable manual distribution mode
	LastMessageTimeout bool   `json:"last_message_timeout"` // Use last message time for timeout calculation
}

// IMMemberInfo contains information about instant messaging member
type IMMemberInfo struct {
	Name  string `json:"name"`   // Member display name
	Sub   string `json:"chat"`   // Chat subscription identifier
	ToSub string `json:"to_sub"` // Target subscription identifier
}

// InboundIMQueue represents a queue for inbound instant messaging attempts
type InboundIMQueue struct {
	BaseQueue
	settings InboundIMQueueSettings
}

// InboundIMQueueFromBytes deserializes InboundIMQueueSettings from JSON bytes
func InboundIMQueueFromBytes(data []byte) InboundIMQueueSettings {
	var settings InboundIMQueueSettings
	json.Unmarshal(data, &settings)
	return settings
}

// NewInboundIMQueue creates a new InboundIMQueue with given settings
func NewInboundIMQueue(base BaseQueue, settings InboundIMQueueSettings) QueueObject {
	if settings.MaxWaitTime == 0 {
		settings.MaxWaitTime = defaultMaxWaitTime
	}

	return &InboundIMQueue{
		BaseQueue: base,
		settings:  settings,
	}
}

// DistributeAttempt initiates distribution of an IM attempt to available agents
func (queue *InboundIMQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	var imInfo IMMemberInfo

	if attempt.member == nil {
		return NewErrorVariableRequired(queue, attempt, "member")
	}
	_ = json.Unmarshal(attempt.member.Destination, &imInfo)

	sess := queue.queueManager.NewIMSession(attempt, imInfo.ToSub, imInfo.Sub)
	go queue.run(attempt, sess, imInfo)

	return nil
}

func (queue *InboundIMQueue) run(attempt *Attempt, sess *im.Session, imInfo IMMemberInfo) {
	defer attempt.Log("stopped queue")

	queue.Hook(HookJoined, attempt)
	attempt.Log("wait agent")

	if err := queue.queueManager.SetFindAgentState(attempt.Id()); err != nil {
		attempt.log.Error("failed to set find agent state",
			wlog.Err(err),
		)
		return
	}

	attempt.SetState(model.MemberStateWaitAgent)
	ags := attempt.On(AttemptHookDistributeAgent)
	attempt.memberChannel = sess

	timeout := time.NewTimer(time.Second * time.Duration(queue.settings.MaxWaitTime))
	defer timeout.Stop()

	var agent agent_manager.AgentObject
	var team *agentTeam
	var task *TaskChannel
	var inviteTimeout *time.Timer

	defer func() {
		if inviteTimeout != nil {
			inviteTimeout.Stop()
		}
	}()

	for {
		select {
		case <-attempt.Cancel():
			queue.finalizeAttempt(attempt, agent, team, task, sess)
			return

		case <-attempt.Context.Done():
			queue.finalizeAttempt(attempt, agent, team, task, sess)
			return

		case <-ags:
			var err *model.AppError
			agent = attempt.Agent()
			team, err = queue.GetTeam(attempt)
			if err != nil {
				attempt.log.Error(err.Error(), wlog.Err(err))
				return
			}

			attempt.Log(fmt.Sprintf("distribute agent %s [%d]", agent.Name(), agent.Id()))

			task = NewTaskChannel(strconv.Itoa(int(attempt.Id())))
			attempt.channelData = task

			inviteTimeout = time.NewTimer(time.Second * time.Duration(team.InviteChatTimeout()))

			team.Distribute(queue, agent, NewDistributeEvent(attempt, agent.UserId(), queue, agent, queue.Processing(), sess, task))
			team.Offering(attempt, agent, task, sess)

			if shouldContinue := queue.handleAgentInteraction(attempt, agent, team, task, sess, timeout, inviteTimeout); !shouldContinue {
				queue.finalizeAttempt(attempt, agent, team, task, sess)
				return
			}

		case <-timeout.C:
			if shouldContinue := queue.handleTimeoutTick(attempt, task, sess, timeout); !shouldContinue {
				queue.finalizeAttempt(attempt, agent, team, task, sess)
				return
			}
		}
	}
}

// handleAgentInteraction processes the interaction between agent and member
func (queue *InboundIMQueue) handleAgentInteraction(
	attempt *Attempt,
	agent agent_manager.AgentObject,
	team *agentTeam,
	task *TaskChannel,
	sess *im.Session,
	timeout *time.Timer,
	inviteTimeout *time.Timer,
) bool {
	for {
		select {
		case state := <-task.stateC:
			inviteTimeout.Stop()

			switch state {
			case TaskStateBridged:
				if err := sess.AddMemberUser(attempt.Context, agent.UserId()); err != nil {
					attempt.Log(err.Error())
				}

				queue.queueManager.NotificationQueue(model.MemberStateBridged, attempt)
				attempt.Log("bridged")
				timeout.Reset(time.Second * time.Duration(imTimerCheckIdle))
				sess.SetActivity()
				team.Bridged(attempt, agent)

			case TaskStateClosed:
				if task.IsDeclined() {
					attempt.Log("conversation declined")
					team.MissedAgentAndWaitingAttempt(attempt, agent)
					attempt.SetState(model.MemberStateWaitAgent)
					attempt.Emit(AttemptHookMissedAgent, agent.Id())
					return true // Continue waiting for another agent
				}
				return false // End the attempt
			}

		case <-inviteTimeout.C:
			queue.handleInviteTimeout(attempt, task)

		case <-timeout.C:
			if shouldContinue := queue.handleTimeoutTick(attempt, task, sess, timeout); !shouldContinue {
				return false
			}
		}
	}
}

// handleTimeoutTick processes periodic timeout checks
func (queue *InboundIMQueue) handleTimeoutTick(
	attempt *Attempt,
	task *TaskChannel,
	sess *im.Session,
	timeout *time.Timer,
) bool {
	shouldContinue := queue.checkIdleTimeouts(attempt, task, sess)
	if shouldContinue {
		timeout.Reset(time.Second * time.Duration(imTimerCheckIdle))
	}
	return shouldContinue
}

// checkIdleTimeouts checks various idle timeout conditions
func (queue *InboundIMQueue) checkIdleTimeouts(attempt *Attempt, task *TaskChannel, sess *im.Session) bool {
	if attempt.bridgedAt == 0 {
		attempt.Log("timeout")
		return false
	}

	wlog.Debug(fmt.Sprintf("attempt [%d] agent_idle=%d member_idle=%d dialog=%d",
		attempt.Id(), sess.OperatorIdleMessage(), sess.MemberIdleMessage(), sess.SilentSec()))

	// Check agent idle timeout
	if queue.settings.MaxIdleAgent > 0 && queue.isAgentIdle(task, sess) {
		attempt.Log("max idle agent")
		attempt.SetResult(AttemptResultAgentTimeout)
		return false
	}

	// Check client idle timeout
	if queue.settings.MaxIdleClient > 0 && queue.isClientIdle(task, sess) {
		attempt.Log("max idle client")
		attempt.SetResult(AttemptResultClientTimeout)
		return false
	}

	// Check dialog idle timeout
	if queue.settings.MaxIdleDialog > 0 && task != nil && sess.SilentSec() >= queue.settings.MaxIdleDialog {
		attempt.Log("max idle dialog")
		attempt.SetResult(AttemptResultDialogTimeout)
		return false
	}

	return true
}

// isAgentIdle checks if agent exceeded idle timeout
func (queue *InboundIMQueue) isAgentIdle(task *TaskChannel, sess *im.Session) bool {
	if task == nil {
		return false
	}

	if queue.settings.LastMessageTimeout {
		return sess.SilentSec() >= queue.settings.MaxIdleAgent &&
			sess.OperatorIdleMessage() > sess.MemberIdleMessage()
	}

	return sess.OperatorIdleMessage() >= queue.settings.MaxIdleAgent
}

// isClientIdle checks if client exceeded idle timeout
func (queue *InboundIMQueue) isClientIdle(task *TaskChannel, sess *im.Session) bool {
	if task == nil {
		return false
	}

	if queue.settings.LastMessageTimeout {
		return sess.SilentSec() >= queue.settings.MaxIdleClient &&
			sess.MemberIdleMessage() > sess.OperatorIdleMessage()
	}

	return sess.MemberIdleMessage() >= queue.settings.MaxIdleClient
}

// handleInviteTimeout handles invitation timeout
func (queue *InboundIMQueue) handleInviteTimeout(attempt *Attempt, task *TaskChannel) {
	attempt.Log("invite timeout")

	if task != nil && task.bridgedAt == 0 {
		task.SetClosed()
	}
}

// finalizeAttempt performs cleanup and finalization when attempt ends
func (queue *InboundIMQueue) finalizeAttempt(
	attempt *Attempt,
	agent agent_manager.AgentObject,
	team *agentTeam,
	task *TaskChannel,
	sess *im.Session,
) {
	if attempt.bridgedAt == 0 {
		task = nil
		team = nil
		agent = nil
	}

	if agent != nil && team != nil {
		if task != nil && task.IsDeclined() && task.ReportingAt() == 0 {
			team.Missed(attempt, agent)
			queue.queueManager.LeavingMember(attempt)
		} else {
			team.Reporting(queue, attempt, agent, task != nil && task.ReportingAt() > 0, false)
		}
	} else {
		queue.queueManager.Abandoned(attempt)
	}

	go queue.cleanupSession(attempt, agent, sess)
}

// cleanupSession performs async cleanup of the session
func (queue *InboundIMQueue) cleanupSession(attempt *Attempt, agent agent_manager.AgentObject, sess *im.Session) {
	attempt.Emit(AttemptHookLeaving)
	attempt.Off("*")

	if agent != nil {
		if err := sess.RemoveMemberUser(context.Background()); err != nil {
			attempt.Log(fmt.Sprintf("failed to remove agent [%d]: %s", agent.Id(), err.Error()))
		}
	}

	queue.queueManager.NotificationQueue(model.MemberStateLeaving, attempt)
	sess.Close()
}
