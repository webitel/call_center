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
	member        *model.MemberAttempt
	state         int
	communication model.MemberCommunication
	resource      ResourceObject
	agent         agent_manager.AgentObject
	domainId      int64
	channel       string
	Info          AttemptInfo `json:"info"`
	Logs          []LogItem   `json:"logs"`
	cancel        chan Result
	done          chan struct{}

	timeout         chan *model.AttemptTimeout
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
		timeout:         make(chan *model.AttemptTimeout),
		distributeAgent: make(chan agent_manager.AgentObject, 1),
		ctx:             context.Background(),
		communication:   model.MemberDestinationFromBytes(member.Destination),
	}
}

func (a *Attempt) SetAgent(agent agent_manager.AgentObject) {
	a.Lock()
	defer a.Unlock()
	a.agent = agent
}

func (a *Attempt) SetState(state int) {
	a.Lock()
	defer a.Unlock()
	a.state = state
}

func (a *Attempt) GetState() int {
	a.RLock()
	defer a.RUnlock()
	return a.state
}

func (a *Attempt) DistributeAgent(agent agent_manager.AgentObject) {
	if a.GetState() != model.MEMBER_STATE_FIND_AGENT {
		return
	}

	a.Lock()
	a.agent = agent
	a.Unlock()

	wlog.Debug(fmt.Sprintf("attempt[%d] distribute agent %d", a.Id(), agent.Id()))

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

func (a *Attempt) Result() string {
	a.RLock()
	defer a.RUnlock()

	if a.member.Result != nil {
		return *a.member.Result
	}
	return ""
}

func (a *Attempt) QueueId() int {
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

func (a *Attempt) AgentId() *int {
	return a.member.AgentId
}

func (a *Attempt) AgentUpdatedAt() *int64 {
	return a.member.AgentUpdatedAt
}

func (a *Attempt) ResourceUpdatedAt() *int64 {
	return a.member.ResourceUpdatedAt
}

func (a *Attempt) Name() string {
	return a.member.Name
}

func (a *Attempt) Display() string {
	if a.communication.Display != nil && *a.communication.Display != "" { //TODO
		return *a.communication.Display
	}
	if a.resource != nil {
		a.communication.Display = model.NewString(a.resource.GetDisplay())
		return *a.communication.Display
	}

	return ""
}

func (a *Attempt) Destination() string {
	//FIXME

	if a.communication.Destination == "" {
		return "FIXME"
	}
	return a.communication.Destination
}

func (a *Attempt) ExportVariables() map[string]string {
	res := make(map[string]string)
	vars := make(map[string]interface{})
	json.Unmarshal(a.member.Variables, &vars)
	for k, v := range vars {
		res[fmt.Sprintf("usr_%s", k)] = fmt.Sprintf("%v", v)
	}
	return res
}

func (a *Attempt) MemberId() int64 {
	return a.member.MemberId
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

func (a *Attempt) WaitTimeout() *model.AttemptTimeout {
	return <-a.timeout
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
