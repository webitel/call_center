package queue

import (
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
)

type OutboundQueueSettings struct {
	processingWithoutAnswer bool
}

type OutboundCallQueue struct {
	CallingQueue
	OutboundQueueSettings
}

func NewOutboundCallQueue(callQueue BaseQueue, withoutAnswer bool) *OutboundCallQueue {

	q := &OutboundCallQueue{
		OutboundQueueSettings: OutboundQueueSettings{
			processingWithoutAnswer: withoutAnswer,
		},
		CallingQueue: CallingQueue{
			BaseQueue: callQueue,
		},
	}

	return q
}

func (queue *OutboundCallQueue) DistributeAttempt(attempt *Attempt) *model.AppError {
	agentChannel, ok := queue.CallManager().GetCall(*attempt.member.MemberCallId)
	if !ok {
		return NewErrorCallRequired(queue, attempt)
	}

	agent := attempt.Agent()
	if agent == nil {
		return NewErrorAgentRequired(queue, attempt)
	}

	team, err := queue.GetTeam(attempt)
	if err != nil {
		attempt.log.Error(err.Error(),
			wlog.Err(err),
		)
		return err
	}

	attempt.agentChannel = agentChannel
	attempt.memberChannel = agentChannel

	go queue.run(attempt, agentChannel, agent, team)

	return nil
}

func (queue *OutboundCallQueue) run(attempt *Attempt, call call_manager.Call, agent agent_manager.AgentObject, team *agentTeam) {
	defer attempt.Log("stopped queue")

	team.Distribute(queue, agent, NewDistributeEvent(attempt, agent.UserId(), queue, agent, queue.Processing(), nil, call))

	team.Offering(attempt, agent, call, nil)
	if call.BridgeAt() > 0 || queue.processingWithoutAnswer {
		team.Bridged(attempt, agent)
	}

	var calling = call.HangupAt() == 0
	for calling && call.HangupCause() == "" {
		select {
		case <-attempt.Cancel():
			calling = false
		case state := <-call.State():
			switch state {
			case call_manager.CALL_STATE_ACCEPT:
				if attempt.state != model.MemberStateBridged {
					team.Bridged(attempt, agent)
				}
				break
			case call_manager.CALL_STATE_BRIDGE:
				if attempt.state != model.MemberStateBridged {
					team.Bridged(attempt, agent)
				}
				break
			case call_manager.CALL_STATE_HANGUP:
				if call.TransferTo() != nil && call.TransferToAgentId() != nil && call.TransferFromAttemptId() != nil {
					attempt.Log("receive transfer")
					if nc, err := queue.GetTransferredCall(*call.TransferTo()); err != nil {
						attempt.log.Error(err.Error(),
							wlog.Err(err),
						)
					} else {
						if nc.HangupAt() == 0 {
							if newA, err := queue.queueManager.TransferFrom(team, attempt, *call.TransferFromAttemptId(), *call.TransferToAgentId(), *call.TransferTo(), nc); err == nil {
								agent = newA
								attempt.Log(fmt.Sprintf("transfer call from [%s] to [%s] AGENT_ID = %s {%d, %d}", call.Id(), nc.Id(), newA.Name(), attempt.Id(), *call.TransferFromAttemptId()))
							} else {
								attempt.log.Error(err.Error(),
									wlog.Err(err),
								)
							}

							call = nc
							continue
						}
					}
				}
				break

			}

		}
	}

	if call.Answered() || queue.processingWithoutAnswer {
		team.Reporting(queue, attempt, agent, call.ReportingAt() > 0, call.Transferred())
	} else if !queue.queueManager.SendAfterDistributeSchema(attempt) {
		team.SetWrap(queue, attempt, agent, "not_answered")
	}

	go func() {
		attempt.Emit(AttemptHookLeaving)
		attempt.Off("*")
	}()
}
