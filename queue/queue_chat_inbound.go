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

type InboundChatQueueSettings struct {
	MaxNoMessageFromClient int    `json:"max_no_message_from"` // канал одлин, сесій багато
	MaxWaitTime            uint32 `json:"max_wait_time"`
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
		settings.MaxWaitTime = 60
	}

	return &InboundChatQueue{
		BaseQueue: base,
		settings:  settings,
	}
}

func (queue *InboundChatQueue) DistributeAttempt(attempt *Attempt) *model.AppError {

	team, err := queue.GetTeam(attempt)
	if err != nil {
		return err
	}

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

	go queue.process(attempt, team, inviterId, invUserId)
	return nil
}

func (queue *InboundChatQueue) process(attempt *Attempt, team *agentTeam, inviterId, invUserId string) {
	var err *model.AppError
	defer attempt.Log("stopped queue")

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

	for loop {
		select {
		case <-attempt.Context.Done():
			conv.SetStop()

		case <-ags:
			agent = attempt.Agent()
			attempt.Log(fmt.Sprintf("distribute agent %s [%d]", agent.Name(), agent.Id()))

			vars := map[string]string{
				model.QUEUE_AGENT_ID_FIELD:   fmt.Sprintf("%d", agent.Id()),
				model.QUEUE_TEAM_ID_FIELD:    fmt.Sprintf("%d", team.Id()),
				model.QUEUE_ID_FIELD:         fmt.Sprintf("%d", queue.Id()),
				model.QUEUE_NAME_FIELD:       queue.Name(),
				model.QUEUE_TYPE_NAME_FIELD:  queue.TypeName(),
				model.QUEUE_ATTEMPT_ID_FIELD: fmt.Sprintf("%d", attempt.Id()),
				"cc_reporting":               fmt.Sprintf("%v", team.PostProcessing()),
			}

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
			queue.Hook(agent, NewDistributeEvent(attempt, agent.UserId(), queue, agent, team.PostProcessing(), conv.MemberSession(), conv.LastSession()))
			team.Offering(attempt, agent, conv.LastSession(), conv.MemberSession())

			wlog.Debug(fmt.Sprintf("conversation [%s] && agent [%s]", conv.MemberSession().Id(), conv.LastSession().Id()))

		top:
			for conv.Active() && conv.LastSession().StopAt == 0 {
				select {
				case <-attempt.Context.Done():
					conv.SetStop()
				case state := <-conv.State():
					switch state {
					case chat.ChatStateInvite:
						attempt.Log("invited")
					case chat.ChatStateDeclined:
						attempt.Log(fmt.Sprintf("conversation decline %s", conv.LastSession().Id()))
						team.MissedAgentAndWaitingAttempt(attempt, agent)
						attempt.Emit(AttemptHookMissedAgent, agent.Id())
						agent = nil

						break top
					case chat.ChatStateBridge:
						attempt.Log("bridged")
						attempt.Emit(AttemptHookBridgedAgent, agent.Id())
						timeout.Reset(time.Second * time.Duration(queue.settings.MaxNoMessageFromClient))
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
				timeout.Reset(time.Second * time.Duration(queue.settings.MaxNoMessageFromClient))
				fmt.Println("TODO TIMEOUT NO MESSAGE CHECK LAST SEND FROM AGENT")
			} else {
				attempt.Log("timeout")
				conv.SetStop()
				break
			}
		}

		loop = conv.Active()
	}

	if agent != nil && conv.BridgedAt() > 0 {
		team.Reporting(attempt, agent, conv.ReportingAt() > 0)
	} else {
		queue.queueManager.Abandoned(attempt)
	}

	go attempt.Emit(AttemptHookLeaving)
	go attempt.Off("*")
	queue.queueManager.LeavingMember(attempt, queue)
}
