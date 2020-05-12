package queue

import (
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/model"
	"time"
)

type InboundChatQueue struct {
	BaseQueue
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
	defer close(attempt.done)

	attempt.Log("wait agent")
	if err = queue.queueManager.SetFindAgentState(attempt.Id()); err != nil {
		//FIXME
		panic(err.Error())
	}
	attempt.SetState(model.MEMBER_STATE_FIND_AGENT)

	timeout := time.NewTimer(time.Second * 30)

	defer timeout.Stop()

	var agent agent_manager.AgentObject

	mChannel := &ChatChannel{
		id: *attempt.member.MemberCallId,
	}

	aChannel := &ChatChannel{
		id: "test",
	}

	for {
		select {
		case agent = <-attempt.distributeAgent:
			attempt.Log(fmt.Sprintf("distribute agent %s [%d]", agent.Name(), agent.Id()))
			// fixme new function
			queue.Hook(model.NewInt(agent.Id()), NewDistributeEvent(attempt, queue, agent, mChannel, aChannel))
			team.Offering(attempt, agent, aChannel, mChannel)
		case <-timeout.C:
			goto end
		}
	}

end:
	if agent != nil {
		team.Missed(attempt, 10, agent)
	} else {
		queue.queueManager.Abandoned(attempt)
	}

	close(attempt.distributeAgent)
	queue.queueManager.LeavingMember(attempt, queue)
}
