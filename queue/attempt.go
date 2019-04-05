package queue

import (
	"encoding/json"
	"fmt"
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
)

type AttemptInfo interface {
	Data() []byte
}

type Attempt struct {
	member *model.MemberAttempt
	info   AttemptInfo
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

func (a *Attempt) Id() int64 {
	return a.member.Id
}

func (a *Attempt) QueueId() int64 {
	return a.member.QueueId
}
func (a *Attempt) QueueUpdatedAt() int64 {
	return a.member.QueueUpdatedAt
}

func (a *Attempt) Name() string {
	return a.member.Name
}

func (a *Attempt) Destination() string {
	return a.member.Destination
}

func (a *Attempt) Description() string {
	return a.member.Description
}

func (a *Attempt) Variables() map[string]string {
	vars := make(map[string]interface{})
	json.Unmarshal(a.member.Variables, vars)
	return model.MapStringInterfaceToString(vars)
}

func (a *Attempt) MemberId() int64 {
	return a.member.MemberId
}

func (a *Attempt) CommunicationId() int64 {
	return a.member.CommunicationId
}

func (a *Attempt) GetCommunicationRoutingId() int {
	if a.member.RoutingId == nil {
		return 0
	}
	return *a.member.RoutingId
}

func (a *Attempt) GetCommunicationPattern() *string {
	return a.member.RoutingPattern
}

func (a *Attempt) Log(info string) {
	mlog.Debug(fmt.Sprintf("Attempt [%v] > %s", a.Id(), info))
	a.logs = append(a.logs, LogItem{
		Time: model.GetMillis(),
		Info: info,
	})
}

func (a *Attempt) LogsData() []byte {
	if a.info != nil {
		return a.info.Data()
	}
	data, _ := json.Marshal(a.logs)
	return data
}
