package queue

import (
	"context"
	"encoding/json"
	"fmt"
	"slices"
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

	// imPreviewGrace is how much longer the thread preview lives than the invite,
	// so an accept arriving at the last moment can still upgrade the preview
	imPreviewGrace = 5 * time.Second

	// imPreviewCallTimeout bounds a single preview RPC
	imPreviewCallTimeout = 5 * time.Second
)

// imInviteDuration returns the invite lifetime of the team, clamped to the preview limit
func imInviteDuration(team *agentTeam) time.Duration {
	d := time.Duration(team.InviteChatTimeout()) * time.Second
	if d > im.MaxPreviewDuration {
		d = im.MaxPreviewDuration
	}
	return d
}

// InboundIMQueueSettings contains configuration for inbound instant messaging queue
type InboundIMQueueSettings struct {
	MaxIdleClient      int64  `json:"max_idle_client"`      // Maximum client idle time in seconds
	MaxIdleAgent       int64  `json:"max_idle_agent"`       // Maximum agent idle time in seconds
	MaxIdleDialog      int64  `json:"max_idle_dialog"`      // Maximum dialog idle time in seconds
	MaxWaitTime        uint32 `json:"max_wait_time"`        // Maximum wait time for agent in seconds
	ManualDistribution bool   `json:"manual_distribution"`  // Enable manual distribution mode
	LastMessageTimeout bool   `json:"last_message_timeout"` // Use last message time for timeout calculation
}

type IMMemberInfo struct {
	Type     string `json:"type"`
	Name     string `json:"name"`
	Iss      string `json:"iss"`
	Sub      string `json:"sub"`
	MemberId string `json:"id,omitempty"`
	Role     int    `json:"role,omitempty"`
}

func (m *IMMemberInfo) IsBot() bool {
	return m.Iss == "bot" || m.Type == "bot"
}

func (m *IMMemberInfo) IsInternalUser() bool {
	return m.Iss == "webitel"
}

type IMThreadInfo struct {
	ID          string         `json:"id"`
	Subject     string         `json:"subject"`
	Members     []IMMemberInfo `json:"members"`
	LastMessage string         `json:"last_msg"`
	Channel     *IMChannel     `json:"channel,omitempty"`
}

func (i *IMThreadInfo) UseSourceChannelIfExists() {
	i.Channel = NewIMChannelFromMembers(i.Members)
}

type IMChannel struct {
	Name string `json:"name"`
	Type string `json:"type"`
}

func NewIMChannelFromMembers(members []IMMemberInfo) *IMChannel {
	botIdx := slices.IndexFunc(members, func(m IMMemberInfo) bool { return m.IsBot() })
	if botIdx == -1 {
		return nil
	}

	externalIdx := slices.IndexFunc(members, func(m IMMemberInfo) bool {
		return !m.IsInternalUser() && !m.IsBot()
	})

	if externalIdx == -1 {
		return nil
	}

	return &IMChannel{
		Name: members[botIdx].Name,
		Type: members[externalIdx].Type,
	}
}

// IMMemberInfo contains information about instant messaging member
type IMThreadCommunication struct {
	Destination string       `json:"destination"`
	Thread      IMThreadInfo `json:"thread"`

	ApiSub    string `json:"api_sub"`    // Chat subscription identifier
	MemberSub string `json:"member_sub"` // Target subscription identifier
	MemberId  string `json:"member_id"`
}

func (t *IMThreadCommunication) Json() []byte {
	data, _ := json.Marshal(t)
	return data
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
	var imInfo IMThreadCommunication

	if attempt.member == nil {
		return NewErrorVariableRequired(queue, attempt, "member")
	}
	_ = json.Unmarshal(attempt.member.Destination, &imInfo)

	sess := queue.queueManager.NewIMSession(attempt, imInfo.ApiSub, imInfo.MemberSub, imInfo.MemberId)
	go queue.run(attempt, sess, imInfo)

	return nil
}

func (queue *InboundIMQueue) run(attempt *Attempt, sess *im.Session, imInfo IMThreadCommunication) {
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
			attempt.Log("finalize: attempt cancel (wait-agent)")
			queue.finalizeAttempt(attempt, agent, team, task, sess, model.IMTimeoutReasonNone)
			return

		case <-attempt.Context.Done():
			attempt.Log("finalize: attempt context done (wait-agent)")
			queue.finalizeAttempt(attempt, agent, team, task, sess, model.IMTimeoutReasonNone)
			return

		case <-sess.Done():
			// DIAG: member IM-сесію скасовано ще до з'єднання з агентом (найімовірніша
			// причина abandoned при трансфері — сесію цього плеча погасив listenEvents).
			attempt.Log(fmt.Sprintf("finalize: session done before bridge (wait-agent) bridged=%v", attempt.bridgedAt > 0))
			queue.finalizeAttempt(attempt, agent, team, task, sess, model.IMTimeoutReasonNone)
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

			// The preview must exist before the invite is sent; a failure means the agent is missed.
			// An agent that is already a thread member is assigned the task without an invite.
			inviteDur := imInviteDuration(team)
			alreadyMember := false
			if perr := queue.givePreview(attempt, agent, sess, inviteDur); perr != nil {
				if !im.IsAlreadyMember(perr) {
					team.MissedAgentAndWaitingAttemptWithError(attempt, agent, perr)
					attempt.SetState(model.MemberStateWaitAgent)
					attempt.Emit(AttemptHookMissedAgent, agent.Id())
					continue
				}

				attempt.Log(fmt.Sprintf("agent [%d] is already a thread member, assign without invite", agent.Id()))
				alreadyMember = true
			}

			inviteTimeout = time.NewTimer(inviteDur)

			team.Distribute(queue, agent, NewDistributeEvent(attempt, agent.UserId(), queue, agent, queue.Processing(), sess, task))
			team.Offering(attempt, agent, task, sess)

			if alreadyMember {
				sess.MarkUserJoined(agent.UserId())
				task.SetAnswered()
			}

			if shouldContinue, reason := queue.handleAgentInteraction(attempt, agent, team, task, sess, timeout, inviteTimeout); !shouldContinue {
				queue.finalizeAttempt(attempt, agent, team, task, sess, reason)
				return
			}

		case <-timeout.C:
			if shouldContinue, reason := queue.handleTimeoutTick(attempt, task, sess, timeout); !shouldContinue {
				queue.finalizeAttempt(attempt, agent, team, task, sess, reason)
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
) (bool, model.IMTimeoutReason) {
	for {
		select {
		case <-sess.Done():
			// DIAG: сесію скасовано під час взаємодії з агентом (offering/bridged).
			attempt.Log(fmt.Sprintf("session done during interaction bridged=%v", attempt.bridgedAt > 0))
			return false, model.IMTimeoutReasonNone
		case state := <-task.stateC:
			inviteTimeout.Stop()

			switch state {
			case TaskStateBridged:
				if err := queue.joinAgent(attempt, agent, sess); err != nil {
					attempt.Log(err.Error())
					queue.removePreview(attempt, agent, sess)
					team.MissedAgentAndWaitingAttemptWithError(attempt, agent, err)
					attempt.SetState(model.MemberStateWaitAgent)
					attempt.Emit(AttemptHookMissedAgent, agent.Id())
					return true, model.IMTimeoutReasonNone // Continue waiting for another agent
				}

				queue.queueManager.NotificationQueue(model.MemberStateBridged, attempt)
				attempt.Log("bridged")
				timeout.Reset(time.Second * time.Duration(imTimerCheckIdle))
				sess.SetActivity()
				team.Bridged(attempt, agent)

			case TaskStateClosed:
				if task.IsDeclined() {
					attempt.Log("conversation declined")
					// Synchronous: must finish before the next agent gets its own preview.
					queue.removePreview(attempt, agent, sess)
					team.MissedAgentAndWaitingAttempt(attempt, agent)
					attempt.SetState(model.MemberStateWaitAgent)
					attempt.Emit(AttemptHookMissedAgent, agent.Id())
					return true, model.IMTimeoutReasonNone // Continue waiting for another agent
				}
				return false, model.IMTimeoutReasonNone // End the attempt
			}

		case <-inviteTimeout.C:
			queue.handleInviteTimeout(attempt, task)

		case <-timeout.C:
			if shouldContinue, reason := queue.handleTimeoutTick(attempt, task, sess, timeout); !shouldContinue {
				return false, reason
			}
		}
	}
}

// givePreview grants the offered agent a read-only preview of the thread for the invite lifetime
// plus a grace period. A zero invite lifetime means no invite preview is needed.
func (queue *InboundIMQueue) givePreview(attempt *Attempt, agent agent_manager.AgentObject, sess *im.Session, d time.Duration) error {
	if d <= 0 {
		return nil
	}

	previewDur := d + imPreviewGrace
	if previewDur > im.MaxPreviewDuration {
		previewDur = im.MaxPreviewDuration
	}

	ctx, cancel := context.WithTimeout(attempt.Context, imPreviewCallTimeout)
	defer cancel()

	if err := sess.GivePreviewUser(ctx, agent.UserId(), previewDur); err != nil {
		attempt.Log(fmt.Sprintf("give preview to agent [%d]: %s", agent.Id(), err.Error()))
		return err
	}

	return nil
}

// removePreview revokes the agent's preview if one is active. It uses a fresh context,
// because it is also called after the attempt context is cancelled.
func (queue *InboundIMQueue) removePreview(attempt *Attempt, agent agent_manager.AgentObject, sess *im.Session) {
	if !sess.HasPreview() {
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), imPreviewCallTimeout)
	defer cancel()

	if err := sess.RemovePreviewUser(ctx); err != nil {
		attempt.Log(fmt.Sprintf("failed to remove preview agent [%d]: %s", agent.Id(), err.Error()))
	}
}

// joinAgent makes the accepted agent a full thread member: it upgrades the preview when one is active,
// otherwise it adds the member directly. An agent that is already a thread member needs no gateway call.
func (queue *InboundIMQueue) joinAgent(attempt *Attempt, agent agent_manager.AgentObject, sess *im.Session) error {
	if sess.IsUserJoined(agent.UserId()) {
		return nil
	}

	if sess.HasPreview() {
		return sess.UpgradePreviewUser(attempt.Context, agent.UserId())
	}

	return sess.AddMemberUser(attempt.Context, agent.UserId())
}

// handleTimeoutTick processes periodic timeout checks
func (queue *InboundIMQueue) handleTimeoutTick(
	attempt *Attempt,
	task *TaskChannel,
	sess *im.Session,
	timeout *time.Timer,
) (bool, model.IMTimeoutReason) {
	shouldContinue, reason := queue.checkIdleTimeouts(attempt, task, sess)
	if shouldContinue {
		timeout.Reset(time.Second * time.Duration(imTimerCheckIdle))
	}
	return shouldContinue, reason
}

// checkIdleTimeouts checks various idle timeout conditions
func (queue *InboundIMQueue) checkIdleTimeouts(attempt *Attempt, task *TaskChannel, sess *im.Session) (bool, model.IMTimeoutReason) {
	if attempt.bridgedAt == 0 {
		attempt.Log("timeout")
		return false, model.IMTimeoutReasonNone
	}

	wlog.Debug(fmt.Sprintf("attempt [%d] agent_idle=%d member_idle=%d dialog=%d",
		attempt.Id(), sess.OperatorIdleMessage(), sess.MemberIdleMessage(), sess.SilentSec()))

	botActive := sess.BotActive()

	// Check agent idle timeout
	if !botActive && queue.settings.MaxIdleAgent > 0 && queue.isAgentIdle(task, sess) {
		attempt.Log("max idle agent")
		attempt.SetResult(AttemptResultAgentTimeout)
		return false, model.IMTimeoutReasonAgent
	}

	// Check client idle timeout
	if !botActive && queue.settings.MaxIdleClient > 0 && queue.isClientIdle(task, sess) {
		attempt.Log("max idle client")
		attempt.SetResult(AttemptResultClientTimeout)
		return false, model.IMTimeoutReasonClient
	}

	// Check dialog idle timeout
	if queue.settings.MaxIdleDialog > 0 && task != nil && sess.SilentSec() >= queue.settings.MaxIdleDialog {
		attempt.Log("max idle dialog")
		attempt.SetResult(AttemptResultDialogTimeout)
		return false, model.IMTimeoutReasonDialog
	}

	return true, model.IMTimeoutReasonNone
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
	endReason model.IMTimeoutReason,
) {
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

	go queue.cleanupSession(attempt, agent, sess, endReason)
}

// cleanupSession performs async cleanup of the session
func (queue *InboundIMQueue) cleanupSession(attempt *Attempt, agent agent_manager.AgentObject, sess *im.Session, endReason model.IMTimeoutReason) {
	if agent != nil {
		queue.removePreview(attempt, agent, sess)

		if err := sess.RemoveMemberUser(context.Background(), endReason); err != nil {
			attempt.Log(fmt.Sprintf("failed to remove agent [%d]: %s", agent.Id(), err.Error()))
		}
	}

	attempt.Emit(AttemptHookLeaving)
	attempt.Off("*")

	queue.queueManager.NotificationQueue(model.MemberStateLeaving, attempt)
	sess.Close(int(attempt.Id()))
}
