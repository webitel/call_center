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
	"strings"
	"sync"
	"time"
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
	AttemptResultTransfer       = "transfer"
	AttemptResultEndless        = "endless"
	AttemptResultMaxWaitSize    = "max_wait_size"
	AttemptResultAgentTimeout   = "agent_timeout"
	AttemptResultClientTimeout  = "client_timeout"
	AttemptResultDialogTimeout  = "dialog_timeout"

	AttemptResultBlockList = "block" // FIXME
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

	result *model.AttemptCallback

	Info    AttemptInfo `json:"info"`
	Logs    []LogItem   `json:"logs"`
	Context context.Context
	sync.RWMutex

	cancel   chan struct{}
	canceled bool

	maxAttempts       uint
	waitBetween       uint64
	perNumbers        bool
	excludeCurrNumber bool
	redial            bool
	description       *string
	stickyAgentId     *int32

	processingForm        model.ProcessingForm
	processingFormStarted bool
	bridgedAt             int64
}

type LogItem struct {
	Time int64  `json:"time"`
	Info string `json:"info"`
}

func NewAttempt(ctx context.Context, member *model.MemberAttempt) *Attempt {
	return &Attempt{
		state:         model.MemberStateIdle,
		member:        member,
		Context:       ctx,
		cancel:        make(chan struct{}),
		communication: model.MemberDestinationFromBytes(member.Destination),
	}
}

// Change attempt settings
func (a *Attempt) AfterDistributeSchema() (*model.SchemaResult, bool) {
	if a.queue == nil {
		return nil, false
	}

	res, ok := a.queue.Manager().AfterDistributeSchema(a)
	if !ok {
		return nil, false
	}
	if res.MaxAttempts > 0 {
		a.maxAttempts = uint(res.MaxAttempts)
		a.Log(fmt.Sprintf("set distribute max attempts %d", a.maxAttempts))
	}
	if res.WaitBetweenRetries > 0 {
		a.waitBetween = uint64(res.WaitBetweenRetries)
		a.Log(fmt.Sprintf("set distribute wait between %d", a.waitBetween))
	}

	if res.ExcludeCurrentNumber {
		a.excludeCurrNumber = true
		a.Log("set exclude current number")
	}

	if res.Description != "" {
		a.description = &res.Description
		a.Log(fmt.Sprintf("set description: %s", res.Description))
	}

	if res.AgentId != 0 {
		a.stickyAgentId = &res.AgentId
		a.Log(fmt.Sprintf("set stickyAgentId: %d", res.AgentId))
	}

	if res.Redial {
		a.redial = true
		a.Log("set redial current number")
	}

	if res.Variables != nil {
		a.AddVariables(res.Variables)
	}

	return res, true
}

func (a *Attempt) MarkProcessingFormStarted() {
	a.Lock()
	a.processingFormStarted = true
	a.Unlock()
}

func (a *Attempt) ProcessingFormStarted() bool {
	a.RLock()
	defer a.RUnlock()

	return a.processingFormStarted
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
	a.result = callback
	if callback.Status != "" {
		a.SetResult(callback.Status)
	}
	a.Unlock()
}

func (a *Attempt) Callback() *model.AttemptCallback {
	a.RLock()
	defer a.RUnlock()
	return a.result
}

func (a *Attempt) SetAgent(agent agent_manager.AgentObject) {
	a.Lock()
	defer a.Unlock()
	a.agent = agent
}

func (a *Attempt) SetState(state string) {
	a.Lock()
	a.state = state
	if state == model.MemberStateBridged && a.bridgedAt == 0 {
		a.bridgedAt = model.GetMillis()
	}
	a.Unlock()

	a.queue.Hook(state, a)
}

func (a *Attempt) GetState() string {
	a.RLock()
	defer a.RUnlock()
	return a.state
}

func (a *Attempt) BridgedAt() int64 {
	a.RLock()
	defer a.RUnlock()

	return a.bridgedAt
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

func (a *Attempt) FlipResource(res *model.AttemptFlipResource) {
	a.member.ResourceId = res.ResourceId
	a.member.ResourceUpdatedAt = res.ResourceUpdatedAt
	a.member.GatewayUpdatedAt = res.GatewayUpdatedAt
	a.member.MemberCallId = res.CallId
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
	if a.communication.Destination == "" {
		return "" // TODO FIXME
	}
	return a.communication.Destination
}

func (a *Attempt) ExportVariables() map[string]string {
	res := make(map[string]string)
	for k, v := range a.member.Variables {
		//todo is bug!
		if a.channel == model.QueueChannelCall && !strings.HasPrefix(k, "sip_h_") {
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

	res["destination"] = a.Destination()
	res["attempt_id"] = fmt.Sprintf("%d", a.Id())
	res["timestamp"] = fmt.Sprintf("%d", model.GetMillis())
	res["joined_at"] = fmt.Sprintf("%d", a.JoinedAt())

	if br := a.BridgedAt(); br > 0 {
		res["bridged_at"] = fmt.Sprintf("%d", br)
	}

	if a.communication.Description != "" {
		res["destination_description"] = a.communication.Description
	}

	if a.communication.Type.Id > 0 {
		res["destination_type"] = fmt.Sprintf("%d", a.communication.Type.Id)
	}

	if a.communication.Attempts >= 0 {
		res["destination_seq"] = fmt.Sprintf("%d", a.communication.Attempts+1) // TODO
	}

	if a.result != nil && a.result.Description != "" {
		res["agent_description"] = a.result.Description
	}

	if a.member.Name != "" {
		res["member_name"] = a.member.Name
	}

	if a.member.MemberId != nil {
		res["member_id"] = strconv.Itoa(int(*a.member.MemberId))
	}

	if a.agentChannel != nil {
		res["agent_channel_id"] = a.agentChannel.Id()
	}
	if a.memberChannel != nil {
		res["member_channel_id"] = a.memberChannel.Id()
		res = model.UnionStringMaps(res, a.memberChannel.Stats())
	}

	if a.MemberStopCause() != "" {
		res["member_stop_cause"] = a.MemberStopCause()
	}

	if ccResult := a.Result(); ccResult != "" {
		res["cc_result"] = ccResult
	}

	resourceId := a.ResourceId()
	if resourceId != nil {
		res["cc_resource_id"] = fmt.Sprintf("%d", *resourceId)
	}

	if a.member != nil && a.member.CommunicationIdx != nil {
		res["communication_id"] = fmt.Sprintf("%d", *a.member.CommunicationIdx)
	}

	if a.queue != nil {
		res["queue_id"] = fmt.Sprintf("%d", a.queue.Id())
		if a.queue.Processing() {
			res["use_processing"] = "true"
		}
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
	a.RLock()
	if a.member != nil && a.member.Variables != nil {
		res, ok = a.member.Variables[name]
	}
	a.RUnlock()

	return
}

func (a *Attempt) AddVariables(vars map[string]string) {
	a.Lock()
	if a.member.Variables == nil {
		a.member.Variables = make(map[string]string)
	}

	for k, v := range vars {
		a.member.Variables[k] = v
	}

	a.Unlock()

	return
}

func (a *Attempt) RemoveVariable(name string) {
	a.Lock()
	if a.member != nil && a.member.Variables != nil {
		delete(a.member.Variables, name)
	}
	a.Unlock()
}

func (a *Attempt) MemberId() *int64 {
	if a.member.MemberId != nil && *a.member.MemberId != 0 {
		return a.member.MemberId
	}
	return nil
}

func (a *Attempt) MemberName() *string {
	if a.member == nil {
		return nil
	}
	return &a.member.Name
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
	//a.Logs = append(a.Logs, LogItem{
	//	Time: model.GetMillis(),
	//	Info: info,
	//})
}

func (a *Attempt) LogsData() []byte {
	data, _ := json.Marshal(a)
	return data
}

func (a *Attempt) ToJSON() string {
	data, _ := json.Marshal(a)
	return string(data)
}

func (a *Attempt) JoinedAt() int64 {
	if a.member != nil {
		return a.member.CreatedAt.UnixNano() / int64(time.Millisecond)
	}

	return 0
}

func (a *Attempt) SetCancel() {
	a.Log("cancel")
	a.Lock()
	defer a.Unlock()
	if !a.canceled {
		a.canceled = true
		close(a.cancel)
	}
}

func (a *Attempt) Cancel() <-chan struct{} {
	return a.cancel
}

func (a *Attempt) Close() {
	if a.processingForm != nil {
		err := a.processingForm.Close()
		if err != nil {
			a.Log(err.Error())
		}
	}
}
