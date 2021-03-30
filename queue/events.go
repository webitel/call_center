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
	AppId           string                    `json:"app_id"`
	Channel         string                    `json:"channel"`
	QueueId         int                       `json:"queue_id"`
	MemberId        *int64                    `json:"member_id"`
	AgentId         *int                      `json:"agent_id"`
	MemberChannelId *string                   `json:"member_channel_id"`
	AgentChannelId  *string                   `json:"agent_channel_id"`
	Communication   model.MemberCommunication `json:"communication"`
	Variables       map[string]string         `json:"variables"`
	HasReporting    bool                      `json:"has_reporting"`
}

type Offering struct {
	MemberChannelId *string `json:"member_channel_id"`
	AgentChannelId  *string `json:"agent_channel_id"`
}

type Missed struct {
	Timeout int64 `json:"timeout"`
}

type Processing struct {
	Timeout    int64  `json:"timeout"`
	RenewalSec uint32 `json:"renewal_sec"`
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

type ProcessingEvent struct {
	ChannelEvent
	Processing Processing `json:"processing"`
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

func NewDistributeEvent(a *Attempt, userId int64, queue QueueObject, agent agent_manager.AgentObject, r bool, mChannel, aChannel Channel) model.Event {
	e := DistributeEvent{
		ChannelEvent: ChannelEvent{
			Timestamp: model.GetMillis(), // todo from attempt!
			Channel:   a.channel,
			AttemptId: model.NewInt64(a.Id()),
			Status:    model.ChannelStateDistribute,
		},
		Distribute: Distribute{
			AppId:         queue.AppId(),
			Communication: a.communication,
			Channel:       queue.Channel(),
			QueueId:       queue.Id(),
			MemberId:      a.MemberId(),
			HasReporting:  r,
		},
	}

	//todo: send all channel variables ?
	if a.channel == model.QueueChannelTask || queue.TypeName() == "progressive" {
		e.Distribute.Variables = a.ExportSchemaVariables()
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

	return model.NewEvent("channel", userId, e)
}

func NewOfferingEvent(a *Attempt, userId int64, timestamp int64, aChannel, mChannel Channel) model.Event {
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

	return model.NewEvent("channel", userId, e)
}

func NewAnsweredEvent(a *Attempt, userId int64, timestamp int64) model.Event {
	e := AnsweredEvent{
		ChannelEvent: ChannelEvent{
			Timestamp: timestamp,
			Channel:   a.channel,
			AttemptId: model.NewInt64(a.Id()),
			Status:    model.ChannelStateAnswered,
		},
	}

	return model.NewEvent("channel", userId, e)
}

func NewBridgedEventEvent(a *Attempt, userId int64, timestamp int64) model.Event {
	e := BridgedEvent{
		ChannelEvent: ChannelEvent{
			Channel:   a.channel,
			AttemptId: model.NewInt64(a.Id()),
			Status:    model.ChannelStateBridged,
			Timestamp: timestamp,
		},
	}

	return model.NewEvent("channel", userId, e)
}

func NewProcessingEventEvent(a *Attempt, userId int64, timestamp int64, deadlineSec uint32, renewal uint32) model.Event {
	e := ProcessingEvent{
		Processing: Processing{
			Timeout:    timestamp + (int64(deadlineSec) * 1000),
			RenewalSec: renewal,
		},
		ChannelEvent: ChannelEvent{
			Timestamp: timestamp,
			Channel:   a.channel,
			AttemptId: model.NewInt64(a.Id()),
			Status:    model.ChannelStateProcessing,
		},
	}

	return model.NewEvent("channel", userId, e)
}

func NewRenewalProcessingEvent(attId int64, userId int64, channel string, timeout, timestamp int64) model.Event {
	e := ProcessingEvent{
		Processing: Processing{
			Timeout:    timeout,
			RenewalSec: 0,
		},
		ChannelEvent: ChannelEvent{
			Timestamp: timestamp,
			Channel:   channel,
			AttemptId: model.NewInt64(attId),
			Status:    model.ChannelStateProcessing,
		},
	}

	return model.NewEvent("channel", userId, e)
}

func NewMissedEventEvent(a *Attempt, userId int64, timestamp int64, timeout int64) model.Event {
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

	return model.NewEvent("channel", userId, e)
}

func NewWrapTimeEventEvent(channel string, attemptId *int64, userId int64, timestamp int64, timeout int64) model.Event {
	e := WrapTimeEvent{
		WrapTime: WrapTime{
			Timeout: timeout,
		},
		ChannelEvent: ChannelEvent{
			Timestamp: timestamp,
			Channel:   channel,
			AttemptId: attemptId,
			Status:    model.ChannelStateWrapTime,
		},
	}

	return model.NewEvent("channel", userId, e)
}

func NewWaitingChannelEvent(channel string, userId int64, attemptId *int64, timestamp int64) model.Event {
	e := WaitingChannelEvent{
		ChannelEvent: ChannelEvent{
			//Channel:   channel,
			Timestamp: timestamp,
			AttemptId: attemptId,
			Status:    model.ChannelStateWaiting,
		},
	}

	return model.NewEvent("channel", userId, e)
}
