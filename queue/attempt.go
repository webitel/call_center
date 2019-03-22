package queue

import (
	"fmt"
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
)

type Attempt struct {
	member *model.MemberAttempt
	logs   []LogItem
}

type LogItem struct {
	Time int64  `json:"time"`
	Info string `json:"info"`
}

func NewAttempt(member *model.MemberAttempt) *Attempt {
	return &Attempt{
		member: member,
	}
}

func (a *Attempt) Name() string {
	return fmt.Sprintf("%v", a.member.MemberId)
}

func (a *Attempt) Id() int64 {
	return a.member.Id
}

func (a *Attempt) MemberId() int64 {
	return a.member.MemberId
}

func (a *Attempt) CommunicationId() int64 {
	return a.member.CommunicationId
}

func (a *Attempt) GetCommunicationPattern() *string {
	return a.member.RoutingPattern
}

func (a *Attempt) SetState() {

}

func (a *Attempt) Log(info string) {
	mlog.Debug(fmt.Sprintf("Attempt [%v] > %s", a.Id(), info))
	a.logs = append(a.logs, LogItem{
		Time: model.GetMillis(),
		Info: info,
	})
}
