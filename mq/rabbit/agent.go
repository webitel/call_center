package rabbit

import (
	"fmt"
	"github.com/webitel/call_center/model"
)

func (a *AMQP) AgentChangeStatus(e model.AgentEventStatus) *model.AppError {
	return a.SendJSON(fmt.Sprintf("events.status.%d.%d", e.DomainId, e.AgentId), []byte(e.ToJSON()))
}

func (a *AMQP) AttemptEvent(e model.EventAttempt) *model.AppError {
	//FIXME add routing queue
	if e.AgentId != nil {
		return a.SendJSON(fmt.Sprintf("events.status.%d.%d", e.DomainId, *e.AgentId), []byte(e.ToJSON()))
	} else {
		return a.SendJSON(fmt.Sprintf("events.status.%d.", e.DomainId), []byte(e.ToJSON()))
	}
}
