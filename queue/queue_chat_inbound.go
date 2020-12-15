package queue

import (
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
	"time"
)

type InboundChatQueueSettings struct {
	HelloMessage string `json:"hello_message"`
}

type InboundChatQueue struct {
	BaseQueue
	settings InboundChatQueueSettings
}

func NewInboundChatQueue(base BaseQueue) QueueObject {
	return &InboundChatQueue{
		BaseQueue: base,
	}
}

type ChatChannel struct {
	id string
}

func (c *ChatChannel) Id() string {
	return c.id
}

func (queue *InboundChatQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	team, err := queue.GetTeam(attempt)
	if err != nil {
		return err
	}

	go queue.process(attempt, team)
	return nil
}

func (queue *InboundChatQueue) process(attempt *Attempt, team *agentTeam) {
	var err *model.AppError
	defer attempt.Log("stopped queue")
	//defer close(attempt.done)

	attempt.Log("wait agent")
	if err = queue.queueManager.SetFindAgentState(attempt.Id()); err != nil {
		//FIXME
		panic(err.Error())
	}
	attempt.SetState(model.MemberStateWaitAgent)

	timeout := time.NewTimer(time.Second * 20)

	defer timeout.Stop()

	var agent agent_manager.AgentObject
	var aChannel *Participant

	mChannel := &ChatChannel{
		id: *attempt.member.MemberCallId,
	}

	ags := attempt.On("agent")

	for {
		select {
		case <-ags:

			agent = attempt.Agent()
			attempt.Log(fmt.Sprintf("distribute agent %s [%d]", agent.Name(), agent.Id()))
			// fixme new function, check error
			agentChannelId, _ := queue.queueManager.store.Member().CreateConversationChannel(mChannel.Id(), agent.Name(), attempt.Id())
			aChannel = NewParticipant(agentChannelId)

			queue.Hook(agent, NewDistributeEvent(attempt, agent.UserId(), queue, agent, mChannel, aChannel))
			team.Offering(attempt, agent, aChannel, mChannel)

			for {
				select {
				case <-timeout.C:
					team.Missed(attempt, 10, agent)
					agent = nil
					goto end

				case state, ok := <-aChannel.StateChannel():
					if !ok {
						goto end
					}

					switch state {
					case ConversationStateBridged:
						timeout.Stop()
						team.Bridged(attempt, agent)
					}
				}
			}

		case <-timeout.C:
			goto end
		}
	}

end:
	if agent != nil {
		wlog.Debug(fmt.Sprintf("attempt[%d] reporting...", attempt.Id()))
		team.Reporting(attempt, agent, true)
	} else {
		queue.queueManager.Abandoned(attempt)
	}
	go attempt.Off("*")
	//close(attempt.distributeAgent)
	queue.queueManager.LeavingMember(attempt, queue)
}
