package agent_manager

import (
	"fmt"
	"github.com/webitel/call_center/model"
)

type AgentObject interface {
}

type Agent struct {
}

type AgentsInAttemptObject interface {
}

type AgentsInAttempt struct {
	agents    []AgentObject
	attemptId int64
}

func NewAgentsInAttempt(agents *model.AgentsForAttempt) AgentsInAttemptObject {
	a := &AgentsInAttempt{
		attemptId: agents.AttemptId,
		agents:    make([]AgentObject, 0, len(agents.AgentIds)),
	}
	fmt.Println(a)
	return a
}
