package queue

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/olebedev/emitter"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
	"strconv"
	"sync"
)

type AttemptInfo interface {
	Data() []byte
}

type Result string

const (
	AttemptHookDistributeAgent  = "agent"
	AttemptHookOfferingAgent    = "offering"
	AttemptHookBridgedAgent     = "bridged"
	AttemptHookMissedAgent      = "missed"
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
	member          *model.MemberAttempt
	memberStopCause *string
	state           string
	communication   model.MemberCommunication
	resource        ResourceObject
	agent           agent_manager.AgentObject
	domainId        int64
	channel         string
	channelData     interface{} // for task queue

	emitter.Emitter
	queue         QueueObject
	agentChannel  Channel
	memberChannel Channel

	agentCallback *model.AttemptCallback

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

func (a *Attempt) SetMemberStopCause(cause *string) {
	a.Lock()
	a.memberStopCause = cause
	a.Unlock()
}

func (a *Attempt) MemberStopCause() string {
	a.RLock()
	defer a.RUnlock()

	if a.memberStopCause == nil {
		return ""
	}

	return *a.memberStopCause
}

func (a *Attempt) SetCallback(callback *model.AttemptCallback) {
	a.Lock()
	a.agentCallback = callback
	a.Unlock()
}

func (a *Attempt) Callback() *model.AttemptCallback {
	a.RLock()
	defer a.RUnlock()
	return a.agentCallback
}

func (a *Attempt) SetAgent(agent agent_manager.AgentObject) {
	a.Lock()
	defer a.Unlock()
	a.agent = agent
}

func (a *Attempt) SetState(state string) {
	a.Lock()
	a.state = state
	a.Unlock()

	a.queue.Hook(state, a)
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

func (a *Attempt) ExportVariables() map[string]string {
	res := make(map[string]string)
	for k, v := range a.member.Variables {
		//todo is bug!
		if a.channel == model.QueueChannelCall {
			res[fmt.Sprintf("usr_%s", k)] = fmt.Sprintf("%v", v)
		} else {
			res[k] = fmt.Sprintf("%v", v)
		}
	}
	if a.member.Seq != nil {
		res[model.QUEUE_ATTEMPT_SEQ] = fmt.Sprintf("%d", *a.member.Seq)
	}

	return res
}

// TODO
func (a *Attempt) ExportSchemaVariables() map[string]string {
	res := make(map[string]string)
	for k, v := range a.member.Variables {
		res[k] = fmt.Sprintf("%v", v)
	}
	if a.member.Seq != nil {
		res[model.QUEUE_ATTEMPT_SEQ] = fmt.Sprintf("%d", *a.member.Seq)
	}

	if a.member.Name != "" {
		res["member_name"] = a.member.Name
	}

	if a.member.MemberId != nil {
		res["member_id"] = strconv.Itoa(int(*a.member.MemberId))
	}

	if a.agent != nil {
		// fixme add to model
		res["agent_name"] = a.agent.Name()
		res["agent_id"] = fmt.Sprintf("%v", a.agent.Id())
		res["user_id"] = fmt.Sprintf("%v", a.agent.UserId())
		res["agent_extension"] = a.agent.CallNumber()
	}

	return res
}

func (a *Attempt) GetVariable(name string) (res string, ok bool) {
	if a.member != nil && a.member.Variables != nil {
		res, ok = a.member.Variables[name]
	}

	return
}

func (a *Attempt) RemoveVariable(name string) {
	if a.member != nil && a.member.Variables != nil {
		delete(a.member.Variables, name)
	}
}

func (a *Attempt) MemberId() *int64 {
	if a.member.MemberId != nil && *a.member.MemberId != 0 {
		return a.member.MemberId
	}
	return nil
}

func (a *Attempt) MemberCallId() *string {
	return a.member.MemberCallId
}

func (a *Attempt) IsBarred() bool {
	if a.member.ListCommunicationId != nil {
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
