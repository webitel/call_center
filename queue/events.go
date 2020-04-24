package queue

import (
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/model"
)

type Channel interface {
	Id() string
}

type ChannelEvent struct {
	AttemptId *int64 `json:"attempt_id,omitempty"` //TODO channel_id ?
	Channel   string `json:"channel"`
	Status    string `json:"status"`
	Timestamp int64  `json:"timestamp"`
}

//TODO refactoring call event to CC
type Distribute struct {
	Channel         string  `json:"channel"`
	QueueId         int     `json:"queue_id"`
	MemberId        int64   `json:"member_id"`
	AgentId         *int    `json:"agent_id"`
	MemberChannelId *string `json:"member_channel_id"`
	AgentChannelId  *string `json:"agent_channel_id"`
}

type Offering struct {
	MemberChannelId *string `json:"member_channel_id"`
	AgentChannelId  *string `json:"agent_channel_id"`
}

type Missed struct {
	Timeout int64 `json:"timeout"`
}

type Reporting struct {
	Timeout int64 `json:"timeout"`
}

type DistributeEvent struct {
	ChannelEvent
	Distribute Distribute `json:"distribute"`
}

type OfferingEvent struct {
	ChannelEvent
	Offering Offering `json:"offering"`
}

type AnsweredEvent struct {
	ChannelEvent
}

type BridgedEvent struct {
	ChannelEvent
}

type ReportingEvent struct {
	ChannelEvent
	Reporting Reporting `json:"reporting"`
}

type WrapTime struct {
	Timeout int64 `json:"timeout"`
}

type MissedEvent struct {
	ChannelEvent
	Missed Missed `json:"missed"`
}

type WrapTimeEvent struct {
	ChannelEvent
	WrapTime WrapTime `json:"wrap_time"`
}

type WaitingChannelEvent struct {
	ChannelEvent
}

func NewDistributeEvent(a *Attempt, queue QueueObject, agent agent_manager.AgentObject, mChannel, aChannel Channel) model.Event {
	e := DistributeEvent{
		ChannelEvent: ChannelEvent{
			Channel:   a.channel,
			AttemptId: model.NewInt64(a.Id()),
			Status:    model.ChannelStateDistribute,
		},
		Distribute: Distribute{
			Channel:  queue.Channel(),
			QueueId:  queue.Id(),
			MemberId: a.MemberId(),
		},
	}

	if agent != nil {
		e.Distribute.AgentId = model.NewInt(agent.Id())
	}

	if mChannel != nil {
		e.Distribute.MemberChannelId = model.NewString(mChannel.Id())
	}

	if aChannel != nil {
		e.Distribute.AgentChannelId = model.NewString(aChannel.Id())
	}

	return model.NewEvent("channel", e)
}

func NewOfferingEvent(a *Attempt, timestamp int64, aChannel, mChannel Channel) model.Event {
	e := OfferingEvent{
		ChannelEvent: ChannelEvent{
			Channel:   a.channel,
			AttemptId: model.NewInt64(a.Id()),
			Timestamp: timestamp,
			Status:    model.ChannelStateOffering,
		},
		Offering: Offering{
			MemberChannelId: nil,
			AgentChannelId:  nil,
		},
	}

	if mChannel != nil {
		e.Offering.MemberChannelId = model.NewString(mChannel.Id())
	}

	if aChannel != nil {
		e.Offering.AgentChannelId = model.NewString(aChannel.Id())
	}

	return model.NewEvent("channel", e)
}

func NewAnsweredEvent(a *Attempt) model.Event {
	e := AnsweredEvent{
		ChannelEvent: ChannelEvent{
			Channel:   a.channel,
			AttemptId: model.NewInt64(a.Id()),
			Status:    model.ChannelStateAnswered,
		},
	}

	return model.NewEvent("channel", e)
}

func NewBridgedEventEvent(a *Attempt) model.Event {
	e := BridgedEvent{
		ChannelEvent: ChannelEvent{
			Channel:   a.channel,
			AttemptId: model.NewInt64(a.Id()),
			Status:    model.ChannelStateBridged,
		},
	}

	return model.NewEvent("channel", e)
}

func NewReportingEventEvent(a *Attempt, timestamp int64, deadlineSec int) model.Event {
	e := ReportingEvent{
		Reporting: Reporting{
			Timeout: timestamp + (int64(deadlineSec) * 1000),
		},
		ChannelEvent: ChannelEvent{
			Timestamp: timestamp,
			Channel:   a.channel,
			AttemptId: model.NewInt64(a.Id()),
			Status:    model.ChannelStateReporting,
		},
	}

	return model.NewEvent("channel", e)
}

func NewMissedEventEvent(a *Attempt, timestamp int64, timeout int64) model.Event {
	e := MissedEvent{
		Missed: Missed{
			Timeout: timeout,
		},
		ChannelEvent: ChannelEvent{
			Channel:   a.channel,
			AttemptId: model.NewInt64(a.Id()),
			Timestamp: timestamp,
			Status:    model.ChannelStateMissed,
		},
	}

	return model.NewEvent("channel", e)
}

func NewWrapTimeEventEvent(a *Attempt, timestamp int64, timeout int64) model.Event {
	e := WrapTimeEvent{
		WrapTime: WrapTime{
			Timeout: timeout,
		},
		ChannelEvent: ChannelEvent{
			Timestamp: timestamp,
			Channel:   a.channel,
			AttemptId: model.NewInt64(a.Id()),
			Status:    model.ChannelStateWrapTime,
		},
	}

	return model.NewEvent("channel", e)
}

func NewWaitingChannelEvent(attemptId *int64, timestamp int64) model.Event {
	e := WaitingChannelEvent{
		ChannelEvent: ChannelEvent{
			Timestamp: timestamp,
			AttemptId: attemptId,
			Status:    model.ChannelStateWaiting,
		},
	}

	return model.NewEvent("channel", e)
}
