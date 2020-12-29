package queue

import (
	"fmt"
	"github.com/webitel/call_center/chat"
	"github.com/webitel/call_center/model"
	"time"
)

type InboundChatQueueSettings struct {
	HelloMessage           string `json:"hello_message"`
	MaxNoMessageFromClient int    `json:"max_no_message_from"` // канал одлин, сесій багато
}

type InboundChatQueue struct {
	BaseQueue
	settings InboundChatQueueSettings
}

func NewInboundChatQueue(base BaseQueue) QueueObject {
	return &InboundChatQueue{
		BaseQueue: base,
		settings: InboundChatQueueSettings{
			HelloMessage:           "hello from queue",
			MaxNoMessageFromClient: 10,
		},
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
	inviterId, ok := attempt.GetVariable("inviter_channel_id")
	if !ok {
		return NewErrorVariableRequired(queue, attempt, "inviter_channel_id")
	}
	//todo
	invUserId, ok := attempt.GetVariable("inviter_user_id")
	if !ok {
		return NewErrorVariableRequired(queue, attempt, "inviter_user_id")
	}

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

	//var agent agent_manager.AgentObject
	//
	//ags := attempt.On(AttemptHookDistributeAgent)
	//TODO

	var timeSec uint32 = 60
	tstWaitAgg := time.NewTicker(time.Second * 20)
	timeout := time.NewTimer(time.Second * time.Duration(timeSec))

	var conv *chat.Conversation
	conv, err = queue.ChatManager().NewConversation(queue.domainId, *attempt.MemberCallId(), inviterId, invUserId,
		model.UnionStringMaps(attempt.ExportVariables(), queue.variables))
	if err != nil {
		//FIXME
		attempt.Log(err.Error())
	}

	if err = conv.SendText("Hello from queue " + queue.name); err != nil {
		attempt.Log(err.Error())
	}

	loop := conv.Active()

	go func() {
		err = conv.InviteInternal(attempt.Context, 10, timeSec, "Q")
		if err != nil {
			//FIXME
			attempt.Log(err.Error())
		}
	}()

	for loop {
		select {
		case <-tstWaitAgg.C:
			fmt.Println("SEND INVITE")

			err = conv.InviteInternal(attempt.Context, 10, timeSec, "Q")
			if err != nil {
				//FIXME
				attempt.Log(err.Error())
			}
			time.Sleep(time.Millisecond * 300)

		case <-timeout.C:
			if conv.BridgedAt() > 0 {
				timeout.Reset(time.Second * time.Duration(queue.settings.MaxNoMessageFromClient))
				fmt.Println("TODO TIMEOUT NO MESSAGE CHECK LAST SEND FROM AGENT")
			} else {
				fmt.Println("TIMEOUT BREAK QUEUE")
				conv.SetStop()
			}

		case state := <-conv.State():
			switch state {
			case chat.ChatStateInvite:
				fmt.Println("QUEUE INVITE")
			case chat.ChatStateDeclined:
				fmt.Println("QUEUE DECLINE")
			case chat.ChatStateBridge:
				fmt.Println("QUEUE BRIDGED")
				conv.SendText(fmt.Sprintf("My name is %s", "{{AGENT_NAME}}"))
				timeout.Reset(time.Second * time.Duration(queue.settings.MaxNoMessageFromClient))
				tstWaitAgg.Stop()

			default:
				fmt.Println("QUEUE ERROR state ", state)
			}
		}

		loop = conv.Active()
	}

	tstWaitAgg.Stop()
	//for conv != nil {
	//	select {
	//	case <-ags:
	//		agent = attempt.Agent()
	//		attempt.Log(fmt.Sprintf("agent %s", agent.Name()))
	//
	//		team.MissedAgentAndWaitingAttempt(attempt, agent)
	//		agent = nil
	//	case <-timeout.C:
	//		attempt.Log("timeout")
	//		goto stop
	//	case <-attempt.Context.Done():
	//		attempt.Log("cancel")
	//		goto stop
	//	}
	//}

	//stop:

	queue.queueManager.Abandoned(attempt)
	go attempt.Emit(AttemptHookLeaving)
	go attempt.Off("*")
	queue.queueManager.LeavingMember(attempt, queue)
}
