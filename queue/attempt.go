package queue

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/olebedev/emitter"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
	"sync"
)

type AttemptInfo interface {
	Data() []byte
}

type Result string

const (
	AttemptHookDistributeAgent  = "agent"
	AttemptHookBridgedAgent     = "bridged"
	AttemptHookLeaving          = "leaving"
	AttemptHookReportingTimeout = "timeout"
)

const (
	AttemptResultAbandoned      = "abandoned"
	AttemptResultSuccess        = "success"
	AttemptResultTimeout        = "timeout"
	AttemptResultPostProcessing = "processing"
	AttemptResultBlockList      = "block" // FIXME
)

type Attempt struct {
	member        *model.MemberAttempt
	state         string
	communication model.MemberCommunication
	resource      ResourceObject
	agent         agent_manager.AgentObject
	domainId      int64
	channel       string

	emitter.Emitter

	Info    AttemptInfo `json:"info"`
	Logs    []LogItem   `json:"logs"`
	Context context.Context
	sync.RWMutex
}

type LogItem struct {
	Time int64  `json:"time"`
	Info string `json:"info"`
}

func NewAttempt(ctx context.Context, member *model.MemberAttempt) *Attempt {
	return &Attempt{
		member:        member,
		Context:       ctx,
		communication: model.MemberDestinationFromBytes(member.Destination),
	}
}

func (a *Attempt) SetAgent(agent agent_manager.AgentObject) {
	a.Lock()
	defer a.Unlock()
	a.agent = agent
}

func (a *Attempt) SetState(state string) {
	a.Lock()
	defer a.Unlock()
	a.state = state
}

func (a *Attempt) GetState() string {
	a.RLock()
	defer a.RUnlock()
	return a.state
}

func (a *Attempt) DistributeAgent(agent agent_manager.AgentObject) {
	if a.GetState() != model.MemberStateWaitAgent {
		return
	}

	a.Lock()
	a.agent = agent
	a.Unlock()

	a.Emit(AttemptHookDistributeAgent, agent)

	wlog.Debug(fmt.Sprintf("attempt[%d] distribute agent %d", a.Id(), agent.Id()))
}

func (a *Attempt) TeamUpdatedAt() *int64 {
	return a.member.TeamUpdatedAt
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

//FIXME
func (a *Attempt) ExportVariables() map[string]string {
	res := make(map[string]string)
	for k, v := range a.member.Variables {
		res[fmt.Sprintf("usr_%s", k)] = fmt.Sprintf("%v", v)
	}
	return res
}

func (a *Attempt) MemberId() *int64 {
	if a.member.MemberId != nil && *a.member.MemberId != 0 {
		return a.member.MemberId
	}
	return nil
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

func (a *Attempt) SetResult(result string) {
	a.member.Result = &result
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
