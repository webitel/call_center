package queue

import (
	"encoding/json"
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/chat"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
	"time"
)

const (
	inviterChannelId = "inviter_channel_id"
	inviterUserId    = "inviter_user_id"

	transferResult = "cc_transfer_result"
)

const (
	timerCheckIdle = 5
)

type InboundChatQueueSettings struct {
	MaxIdleClient      int64  `json:"max_idle_client"`
	MaxIdleAgent       int64  `json:"max_idle_agent"`
	MaxIdleDialog      int64  `json:"max_idle_dialog"`
	MaxWaitTime        uint32 `json:"max_wait_time"`
	ManualDistribution bool   `json:"manual_distribution"`
	LastMessageTimeout bool   `json:"last_message_timeout"`
}

type InboundChatQueue struct {
	BaseQueue
	settings InboundChatQueueSettings
}

func InboundChatQueueFromBytes(data []byte) InboundChatQueueSettings {
	var settings InboundChatQueueSettings
	json.Unmarshal(data, &settings)
	return settings
}

func NewInboundChatQueue(base BaseQueue, settings InboundChatQueueSettings) QueueObject {
	if settings.MaxWaitTime == 0 {
		settings.MaxWaitTime = 300
	}

	return &InboundChatQueue{
		BaseQueue: base,
		settings:  settings,
	}
}

func (queue *InboundChatQueue) DistributeAttempt(attempt *Attempt) *model.AppError {

	if attempt.MemberCallId() == nil {
		return NewErrorCallRequired(queue, attempt)
	}

	//todo
	inviterId, ok := attempt.GetVariable(inviterChannelId)
	if !ok {
		return NewErrorVariableRequired(queue, attempt, inviterChannelId)
	}
	//todo
	invUserId, ok := attempt.GetVariable(inviterUserId)
	if !ok {
		return NewErrorVariableRequired(queue, attempt, inviterUserId)
	}
	attempt.RemoveVariable(inviterChannelId)
	attempt.RemoveVariable(inviterUserId)

	attempt.manualDistribution = queue.settings.ManualDistribution

	go queue.process(attempt, inviterId, invUserId)
	return nil
}

func (queue *InboundChatQueue) process(attempt *Attempt, inviterId, invUserId string) {
	var err *model.AppError
	var team *agentTeam
	var timeoutStrategy bool

	defer attempt.Log("stopped queue")

	queue.Hook(HookJoined, attempt)

	attempt.Log("wait agent")
	if err = queue.queueManager.SetFindAgentState(attempt.Id()); err != nil {
		//FIXME
		panic(err.Error())
	}
	attempt.SetState(model.MemberStateWaitAgent)

	var agent agent_manager.AgentObject
	ags := attempt.On(AttemptHookDistributeAgent)

	var timeSec = queue.settings.MaxWaitTime
	timeout := time.NewTimer(time.Second * time.Duration(timeSec))

	var conv *chat.Conversation
	conv, err = queue.ChatManager().NewConversation(queue.domainId, *attempt.MemberCallId(), inviterId, invUserId,
		model.UnionStringMaps(attempt.ExportVariables(), queue.variables))
	if err != nil {
		attempt.Log(err.Error())
		queue.queueManager.Abandoned(attempt)
		go func() {
			attempt.Emit(AttemptHookLeaving)
			attempt.Off("*")
		}()
		return
	}

	loop := conv.Active()

	mSess := conv.MemberSession()
	attempt.memberChannel = mSess
	var aSess *chat.ChatSession

	for loop {
		select {
		case <-attempt.Cancel():
			conv.SetStop()
			loop = false
			break
		case <-attempt.Context.Done():
			conv.SetStop()

		case <-ags:
			agent = attempt.Agent()
			team, err = queue.GetTeam(attempt)
			if err != nil {
				wlog.Error(err.Error())
				return
			}
			attempt.Log(fmt.Sprintf("distribute agent %s [%d]", agent.Name(), agent.Id()))

			vars := model.UnionStringMaps(
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
			}

			//todo close
			err = conv.InviteInternal(attempt.Context, agent.UserId(), team.InviteChatTimeout(), queue.name, vars)
			if err != nil {
				attempt.Log(err.Error())

				if err == chat.ErrChannelNotFound {
					team.CancelAgentAttempt(attempt, agent)
					loop = false
				} else {
					team.MissedAgentAndWaitingAttempt(attempt, agent)
					attempt.SetState(model.MemberStateWaitAgent)
				}

				agent = nil
				team = nil
				continue
			}

			attempt.Emit(AttemptHookOfferingAgent, agent.Id())
			// fixme new function
			aSess = conv.LastSession()
			team.Distribute(queue, agent, NewDistributeEvent(attempt, agent.UserId(), queue, agent, queue.Processing(), mSess, aSess))

			wlog.Debug(fmt.Sprintf("conversation [%s] && agent [%s]", conv.MemberSession().Id(), conv.LastSession().Id()))

		top:
			for conv.Active() && aSess.StopAt() == 0 { //
				select {
				case <-attempt.Cancel():
					conv.SetStop()
					loop = false
					break
				case <-timeout.C:
					if conv.BridgedAt() > 0 {
						//wlog.Debug(fmt.Sprintf("attempt [%d] agent_idle=%d member_idle=%d dialog=%d", attempt.Id(), aSess.IdleSec(), mSess.IdleSec(), conv.SilentSec()))

						if queue.settings.LastMessageTimeout {
							timeoutStrategy = aSess != nil && conv.SilentSec() >= queue.settings.MaxIdleAgent && mSess.IdleSec() > aSess.IdleSec()
						} else {
							timeoutStrategy = aSess != nil && aSess.IdleSec() >= queue.settings.MaxIdleAgent
						}

						if queue.settings.MaxIdleAgent > 0 && timeoutStrategy {
							attempt.Log("max idle agent")
							attempt.SetResult(AttemptResultAgentTimeout)
							aSess.Leave(model.AgentTimeout)
							break
						}

						if queue.settings.LastMessageTimeout {
							timeoutStrategy = aSess != nil && conv.SilentSec() >= queue.settings.MaxIdleClient && aSess.IdleSec() > mSess.IdleSec()
						} else {
							timeoutStrategy = aSess != nil && mSess.IdleSec() >= queue.settings.MaxIdleClient
						}

						if queue.settings.MaxIdleClient > 0 && timeoutStrategy {
							attempt.Log("max idle client")
							attempt.SetResult(AttemptResultClientTimeout)
							aSess.Leave(model.ClientTimeout)
							break
						}

						if queue.settings.MaxIdleDialog > 0 && aSess != nil && conv.SilentSec() >= queue.settings.MaxIdleDialog {
							attempt.Log("max idle dialog")
							attempt.SetResult(AttemptResultDialogTimeout)
							aSess.Leave(model.SilenceTimeout)
							break
						}

						timeout.Reset(time.Second * time.Duration(timerCheckIdle))
					} else {
						attempt.Log("timeout")
						conv.SetStop()
						break
					}
				case <-attempt.Context.Done():
					conv.SetStop()
				case state := <-conv.State():
					switch state {
					case chat.ChatStateInvite:
						attempt.Log("invited")
						attempt.agentChannel = mSess
						team.Offering(attempt, agent, aSess, conv.MemberSession())
					case chat.ChatStateDeclined:
						attempt.Log(fmt.Sprintf("conversation decline %s", conv.LastSession().Id()))
						team.MissedAgentAndWaitingAttempt(attempt, agent)
						attempt.SetState(model.MemberStateWaitAgent)

						attempt.Emit(AttemptHookMissedAgent, agent.Id())
						agent = nil
						aSess = nil

						break top
					case chat.ChatStateBridge:
						mSess.SetActivity()
						attempt.Log("bridged")
						attempt.Emit(AttemptHookBridgedAgent, agent.Id())
						timeout.Reset(time.Second * time.Duration(timerCheckIdle))
						team.Bridged(attempt, agent)
					case chat.ChatStateClose:
						attempt.Log("closed cause:" + conv.Cause())
						conv.SetStop()

					default:
						fmt.Println("QUEUE ERROR state ", state)
					}
				}
			}

		case <-timeout.C:
			if conv.BridgedAt() > 0 {
				timeout.Reset(time.Second * time.Duration(timerCheckIdle))
			} else {
				attempt.Log("timeout")
				conv.SetStop()
				break
			}
		}

		loop = conv.Active()
	}

	if agent != nil && team != nil {
		if aSess != nil && aSess.StopAt() == 0 {
			// TODO: what reason is this?
			aSess.Close("")
		}
		transferred := conv.Cause() == "transfer"
		if transferred {
			attempt.MarkTransferred()
		}
		transferredProcessing := transferred &&
			queue.GetVariable(transferResult) == model.MEMBER_CAUSE_ABANDONED

		if conv.BridgedAt() > 0 && !transferredProcessing {
			team.Reporting(queue, attempt, agent, conv.ReportingAt() > 0, transferred)
		} else {
			team.Missed(attempt, agent)
			queue.queueManager.LeavingMember(attempt)
		}
	} else {
		queue.queueManager.Abandoned(attempt)
	}

	go func() {
		attempt.Emit(AttemptHookLeaving)
		attempt.Off("*")
	}()

	queue.queueManager.app.ChatManager().RemoveConversation(conv)
}
