package agent_manager

import (
	"fmt"
	"github.com/webitel/call_center/model"
)

type Agent struct {
	info *model.Agent
}

func NewAgent(info *model.Agent) AgentObject {
	return &Agent{
		info: info,
	}
}

func (agent *Agent) Name() string {
	return agent.info.Name
}

func (agent *Agent) Id() int64 {
	return agent.info.Id
}

func (agent *Agent) IsExpire(updatedAt int64) bool {
	return agent.info.UpdatedAt != updatedAt
}

func (agent *Agent) CallDestination() string {
	return "user/9999@10.10.10.144"
}

func (agent *Agent) CallError(err *model.AppError, cause string) {
	switch cause {
	case model.CALL_HANGUP_NO_ANSWER:
		fmt.Println("CALL_HANGUP_NO_ANSWER")
	case model.CALL_HANGUP_REJECTED:
		fmt.Println("CALL_HANGUP_REJECTED")
	default:
		fmt.Println("OTHER")
	}
}

func (agent *Agent) SetState(state string) *model.AppError {
	return nil
}
