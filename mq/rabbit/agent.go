package rabbit

import (
	"fmt"
	"github.com/webitel/call_center/model"
)

func (a *AMQP) AgentChangeStatus(e model.AgentEventStatus) *model.AppError {
	return a.SendJSON(fmt.Sprintf("events.status.%d.%d", e.DomainId, e.AgentId), []byte(e.ToJSON()))
}
