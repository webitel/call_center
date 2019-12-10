package queue

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
	"sync"
)

type AttemptInfo interface {
	Data() []byte
}

type Result string

type Attempt struct {
	member          *model.MemberAttempt
	resource        ResourceObject
	agent           agent_manager.AgentObject
	Info            AttemptInfo `json:"info"`
	Logs            []LogItem   `json:"logs"`
	cancel          chan Result
	done            chan struct{}
	distributeAgent chan agent_manager.AgentObject
	ctx             context.Context
	sync.RWMutex
}

type LogItem struct {
	Time int64  `json:"time"`
	Info string `json:"info"`
}

func NewAttempt(member *model.MemberAttempt) *Attempt {
	return &Attempt{
		member:          member,
		cancel:          make(chan Result, 1),
		done:            make(chan struct{}),
		distributeAgent: make(chan agent_manager.AgentObject, 1),
		ctx:             context.Background(),
	}
}

func (a *Attempt) SetAgent(agent agent_manager.AgentObject) {
	a.Lock()
	defer a.Unlock()
	a.agent = agent
}

func (a *Attempt) DistributeAgent(agent agent_manager.AgentObject) {
	a.Lock()
	a.agent = agent
	a.Unlock()

	a.distributeAgent <- agent
}

func (a *Attempt) TeamUpdatedAt() *int64 {
	return a.member.TeamUpdatedAt
}

func (a *Attempt) Done() {
	close(a.done)
}

func (a *Attempt) SetMember(member *model.MemberAttempt) {
	if a.Id() == member.Id {
		a.member = member
		if a.member.Result != nil {
			a.Log(fmt.Sprintf("set result %s", *member.Result))
			a.cancel <- Result(*a.member.Result)
		}
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

func (a *Attempt) ResourceId() *int64 {
	return a.member.ResourceId
}

func (a *Attempt) Agent() agent_manager.AgentObject {
	return a.agent
}

func (a *Attempt) ResourceUpdatedAt() *int64 {
	return a.member.ResourceUpdatedAt
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

func (a *Attempt) IsBarred() bool {
	if a.member.Result != nil && *a.member.Result == model.CALL_HANGUP_OUTGOING_CALL_BARRED {
		return true
	}
	return false
}

func (a *Attempt) IsTimeout() bool {
	return a.member.IsTimeout()
}

func (a *Attempt) SetResult(result *string) {
	a.member.Result = result
}

func (a *Attempt) Log(info string) {
	wlog.Debug(fmt.Sprintf("attempt [%v] > %s", a.Id(), info))
	a.Logs = append(a.Logs, LogItem{
		Time: model.GetMillis(),
		Info: info,
	})
}

func (a *Attempt) LogsData() []byte {
	data, _ := json.Marshal(a)
	return data
}

func (a *Attempt) ToJSON() string {
	data, _ := json.Marshal(a)
	return string(data)
}
