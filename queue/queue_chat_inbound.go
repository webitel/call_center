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
)

const (
	timerCheckIdle = 5
)

type InboundChatQueueSettings struct {
	MaxIdleClient int64  `json:"max_idle_client"`
	MaxIdleAgent  int64  `json:"max_idle_agent"`
	MaxWaitTime   uint32 `json:"max_wait_time"`
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

	if settings.MaxIdleClient == 0 {
		settings.MaxIdleClient = 86400
	}

	if settings.MaxIdleAgent == 0 {
		settings.MaxIdleAgent = 86400
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

	go queue.process(attempt, inviterId, invUserId)
	return nil
}

func (queue *InboundChatQueue) process(attempt *Attempt, inviterId, invUserId string) {
	var err *model.AppError
	var team *agentTeam
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

	var timeSec uint32 = queue.settings.MaxWaitTime
	timeout := time.NewTimer(time.Second * time.Duration(timeSec))

	var conv *chat.Conversation
	conv, err = queue.ChatManager().NewConversation(queue.domainId, *attempt.MemberCallId(), inviterId, invUserId,
		model.UnionStringMaps(attempt.ExportVariables(), queue.variables))
	if err != nil {
		//FIXME
		attempt.Log(err.Error())
	}

	loop := conv.Active()

	mSess := conv.MemberSession()
	var aSess *chat.ChatSession

	for loop {
		select {
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

			vars := map[string]string{
				model.QUEUE_AGENT_ID_FIELD:   fmt.Sprintf("%d", agent.Id()),
				model.QUEUE_TEAM_ID_FIELD:    fmt.Sprintf("%d", team.Id()),
				model.QUEUE_ID_FIELD:         fmt.Sprintf("%d", queue.Id()),
				model.QUEUE_NAME_FIELD:       queue.Name(),
				model.QUEUE_TYPE_NAME_FIELD:  queue.TypeName(),
				model.QUEUE_ATTEMPT_ID_FIELD: fmt.Sprintf("%d", attempt.Id()),
				"cc_reporting":               fmt.Sprintf("%v", queue.Processing()),
			}

			//todo close
			err = conv.InviteInternal(attempt.Context, agent.UserId(), team.CallTimeout(), queue.name, vars)
			if err != nil {
				// todo
				attempt.Log(err.Error())
				team.MissedAgentAndWaitingAttempt(attempt, agent)
				agent = nil
				continue
			}

			attempt.Emit(AttemptHookOfferingAgent, agent.Id())
			// fixme new function
			aSess = conv.LastSession()
			team.Distribute(queue, agent, NewDistributeEvent(attempt, agent.UserId(), queue, agent, queue.Processing(), mSess, aSess))

			wlog.Debug(fmt.Sprintf("conversation [%s] && agent [%s]", conv.MemberSession().Id(), conv.LastSession().Id()))

		top:
			for conv.Active() && aSess.StopAt == 0 {
				select {
				case <-timeout.C:
					if conv.BridgedAt() > 0 {
						//wlog.Debug(fmt.Sprintf("attempt [%d] agent_idle=%d member_idle=%d", attempt.Id(), aSess.IdleSec(), mSess.IdleSec()))

						if aSess != nil && aSess.IdleSec() >= queue.settings.MaxIdleAgent {
							attempt.Log("max idle agent")
							aSess.Leave()
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
						team.Offering(attempt, agent, conv.LastSession(), conv.MemberSession())
					case chat.ChatStateDeclined:
						attempt.Log(fmt.Sprintf("conversation decline %s", conv.LastSession().Id()))
						team.MissedAgentAndWaitingAttempt(attempt, agent)
						attempt.SetState(model.MemberStateWaitAgent)

						attempt.Emit(AttemptHookMissedAgent, agent.Id())
						agent = nil
						aSess = nil

						break top
					case chat.ChatStateBridge:
						attempt.Log("bridged")
						attempt.Emit(AttemptHookBridgedAgent, agent.Id())
						timeout.Reset(time.Second * time.Duration(timerCheckIdle))
						team.Bridged(attempt, agent)
					case chat.ChatStateClose:
						attempt.Log("closed")
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
		if conv.BridgedAt() > 0 {
			team.Reporting(queue, attempt, agent, conv.ReportingAt() > 0, false)
		} else {
			team.Missed(attempt, agent)
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
