package agent_manager

import (
	"fmt"
	"github.com/webitel/call_center/model"
)

type Agent struct {
	info    *model.Agent
	manager AgentManager
}

func NewAgent(info *model.Agent, am AgentManager) AgentObject {
	return &Agent{
		info:    info,
		manager: am,
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

func (agent *Agent) LeggedIn() *model.AppError {
	return nil
}

func (agent *Agent) LeggedOut() *model.AppError {
	return nil
}

func (agent *Agent) SetState(state string) *model.AppError {
	return nil
}

func (agent *Agent) SetWaiting() {

}

func (agent *Agent) OfferingCall(callRequest *model.CallRequest) { //(string, string, *model.AppError)

}

func (agent *Agent) SetMute(on bool) {
	//uuid_audio 0d7c3b93-a5ae-4964-9e4d-902bba50bd19 start write mute
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
