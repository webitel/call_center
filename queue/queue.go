package queue

import (
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/chat"
	"github.com/webitel/call_center/model"
	"github.com/webitel/flow_manager/client"
	"github.com/webitel/wlog"
	"net/http"
)

type QueueObject interface {
	Name() string
	IsExpire(int64) bool
	TypeName() string
	Manager() *QueueManager

	DistributeAttempt(attempt *Attempt) *model.AppError

	Variables() map[string]string
	Domain() string
	DomainId() int64
	Channel() string
	Id() int
	AppId() string

	Leaving(attempt *Attempt)

	ProcessingTransfer() bool
	Processing() bool
	ProcessingSec() uint32
	ProcessingRenewalSec() uint32
	Hook(name string, at *Attempt)
	Endless() bool

	DoSchemaId() *int32
	AfterSchemaId() *int32
	HasForm() bool
	StartProcessingForm(attempt *Attempt)
	AutoAnswer() bool
	RingtoneUri() string
	AmdPlaybackUri() *string // todo move to amd
}

type BaseQueue struct {
	channel              string
	id                   int
	updatedAt            int64
	domainId             int64
	domainName           string
	typeId               int8
	name                 string
	resourceManager      *ResourceManager
	queueManager         *QueueManager
	variables            map[string]string
	teamId               *int
	schemaId             *int
	ringtone             *model.RingtoneFile
	ringtoneUri          *string
	doSchema             *int32
	afterSchemaId        *int32
	formSchemaId         *int
	processing           bool
	processingSec        uint32
	processingRenewalSec uint32
	endless              bool
	hooks                HookHub
	amdPlaybackFileUri   *string
}

func NewBaseQueue(queueManager *QueueManager, resourceManager *ResourceManager, settings *model.Queue) BaseQueue {
	base := BaseQueue{
		channel:              settings.Channel(),
		id:                   settings.Id,
		updatedAt:            settings.UpdatedAt,
		domainId:             settings.DomainId,
		domainName:           settings.DomainName,
		typeId:               int8(settings.Type),
		name:                 settings.Name,
		resourceManager:      resourceManager,
		queueManager:         queueManager,
		variables:            settings.Variables,
		teamId:               settings.TeamId,
		schemaId:             settings.SchemaId,
		doSchema:             settings.DoSchemaId,
		afterSchemaId:        settings.AfterSchemaId,
		formSchemaId:         settings.FormSchemaId,
		processing:           settings.Processing,
		processingSec:        settings.ProcessingSec,
		processingRenewalSec: settings.ProcessingRenewalSec,
		endless:              settings.Endless,
		hooks:                NewHookHub(settings.Hooks),
	}

	if settings.RingtoneId != nil && settings.RingtoneType != nil {
		base.ringtone = &model.RingtoneFile{
			Id:   *settings.RingtoneId,
			Type: *settings.RingtoneType,
		}
		base.ringtoneUri = model.NewString(model.RingtoneUri(base.domainId, base.ringtone.Id, base.ringtone.Type))
	}

	if settings.AmdPlaybackFile != nil {
		base.amdPlaybackFileUri = model.NewString(model.RingtoneUri(base.domainId, settings.AmdPlaybackFile.Id, settings.AmdPlaybackFile.Type))
	}

	if settings.GranteeId != nil {
		base.variables[model.CallVariableGrantee] = fmt.Sprintf("%d", *settings.GranteeId)
	}

	return base
}

func NewQueue(queueManager *QueueManager, resourceManager *ResourceManager, settings *model.Queue) (QueueObject, *model.AppError) {
	base := NewBaseQueue(queueManager, resourceManager, settings)

	switch settings.Type {
	case model.QueueTypeOfflineCall:
		return NewOfflineCallQueue(CallingQueue{
			BaseQueue: base,
			HoldMusic: settings.HoldMusic,
			granteeId: settings.GranteeId,
		}, QueueOfflineSettingsFromBytes(settings.Payload)), nil

	case model.QueueTypeInboundCall:
		inboundSettings := model.QueueInboundSettingsFromBytes(settings.Payload)
		return NewInboundQueue(CallingQueue{
			BaseQueue: base,
			HoldMusic: settings.HoldMusic,
			granteeId: settings.GranteeId,
		}, inboundSettings), nil

	case model.QueueTypeIVRCall:
		return NewIVRQueue(CallingQueue{
			BaseQueue: base,
			HoldMusic: settings.HoldMusic,
			granteeId: settings.GranteeId,
		}, QueueIVRSettingsFromBytes(settings.Payload)), nil

	case model.QueueTypePreviewCall:
		return NewPreviewCallQueue(CallingQueue{
			BaseQueue: base,
			HoldMusic: settings.HoldMusic,
			granteeId: settings.GranteeId,
		}, PreviewSettingsFromBytes(settings.Payload)), nil

	case model.QueueTypeProgressiveCall:
		return NewProgressiveCallQueue(CallingQueue{
			BaseQueue: base,
			HoldMusic: settings.HoldMusic,
			granteeId: settings.GranteeId,
		}, ProgressiveSettingsFromBytes(settings.Payload)), nil

	case model.QueueTypePredictCall:
		return NewPredictCallQueue(CallingQueue{
			BaseQueue: base,
			HoldMusic: settings.HoldMusic,
			granteeId: settings.GranteeId,
		}, PredictCallQueueSettingsFromBytes(settings.Payload)), nil

	case model.QueueTypeInboundChat:
		return NewInboundChatQueue(base, InboundChatQueueFromBytes(settings.Payload)), nil

	case model.QueueTypeAgentTask:
		return NewTaskAgentQueue(base, TaskAgentSettingsFromBytes(settings.Payload)), nil

	case model.QueueTypeOutboundTask:
		return NewTaskOutboundQueue(base, TaskOutboundQueueSettingsFromBytes(settings.Payload)), nil

	default:
		return nil, model.NewAppError("Dialing.NewQueue", "dialing.queue.new_queue.app_error", nil,
			fmt.Sprintf("Queue type %v not implement", settings.Type), http.StatusInternalServerError)
	}
}

func (queue *BaseQueue) HasForm() bool {
	return queue.formSchemaId != nil && queue.Processing()
}

func (queue *BaseQueue) Manager() *QueueManager {
	return queue.queueManager
}

func (queue *BaseQueue) DoSchemaId() *int32 {
	return queue.doSchema
}

func (queue *BaseQueue) AfterSchemaId() *int32 {
	return queue.afterSchemaId
}

func (queue *BaseQueue) AppId() string {
	return queue.queueManager.app.GetInstanceId()
}

func (queue *BaseQueue) IsExpire(updatedAt int64) bool {
	return queue.updatedAt != updatedAt
}

func (queue *BaseQueue) FlowManager() client.FlowManager {
	return queue.queueManager.app.FlowManager()
}

func (queue *BaseQueue) Name() string {
	return queue.name
}

func (queue *BaseQueue) TeamManager() *teamManager {
	return queue.queueManager.teamManager
}

func (queue *BaseQueue) GetTeam(attempt *Attempt) (*agentTeam, *model.AppError) {
	if attempt.agent != nil {
		return queue.TeamManager().GetTeam(attempt.agent.TeamId(), attempt.agent.TeamUpdatedAt())
	}

	return nil, model.NewAppError("BaseQueue.GetTeam", "queue.team.get_by_id.app_error", nil, "Not found parameters", http.StatusInternalServerError)
}

func (queue *BaseQueue) Processing() bool {
	return queue.processing
}

func (queue *BaseQueue) ProcessingSec() uint32 {
	return queue.processingSec
}

func (queue *BaseQueue) ProcessingRenewalSec() uint32 {
	return queue.processingRenewalSec
}

func (queue *BaseQueue) TypeName() string {
	switch queue.typeId {
	case model.QueueTypeOfflineCall:
		return "offline"
	case model.QueueTypeInboundCall:
		return "inbound"
	case model.QueueTypeIVRCall:
		return "ivr"
	case model.QueueTypePreviewCall:
		return "preview"
	case model.QueueTypeProgressiveCall:
		return "progressive"
	case model.QueueTypePredictCall:
		return "predictive"
	case model.QueueTypeInboundChat:
		return "inbound chat"
	case model.QueueTypeAgentTask:
		return "task"
	case model.QueueTypeOutboundTask:
		return "outbound_task"
	default:
		return "NOT_IMPLEMENT"
	}
}

func (queue *BaseQueue) Variables() map[string]string {
	return queue.variables
}

// TODO create queue parameter auto_answer

func (q *BaseQueue) AutoAnswer() bool {
	if q.variables != nil {
		if v, ok := q.variables[model.QueueAutoAnswerVariable]; ok && (v != "false") {
			return true
		}
	}

	return false
}

func (q *BaseQueue) Domain() string {
	return q.domainName
}

func (q *BaseQueue) DomainId() int64 {
	return q.domainId
}

func (queue *BaseQueue) Id() int {
	return queue.id
}

func (queue *BaseQueue) CallManager() call_manager.CallManager {
	return queue.queueManager.callManager
}

func (queue *BaseQueue) ChatManager() *chat.ChatManager {
	return queue.queueManager.app.ChatManager()
}

func (queue *BaseQueue) AgentManager() agent_manager.AgentManager {
	return queue.queueManager.agentManager
}

func (queue *BaseQueue) Channel() string {
	return queue.channel
}

func (queue *BaseQueue) Endless() bool {
	return queue.endless
}

func (queue *BaseQueue) StartProcessingForm(attempt *Attempt) {
	if queue.formSchemaId != nil && queue.Processing() && !attempt.ProcessingFormStarted() {
		go queue.queueManager.StartProcessingForm(*queue.formSchemaId, attempt)
	}
}

// todo config
func (qeueu *BaseQueue) ProcessingTransfer() bool {
	return false
}

func (queue *BaseQueue) Leaving(attempt *Attempt) {
	queue.queueManager.LeavingMember(attempt)
}

func (tm *agentTeam) Distribute(queue QueueObject, agent agent_manager.AgentObject, e model.Event) {
	if err := tm.teamManager.mq.AgentChannelEvent(queue.Channel(), queue.DomainId(), queue.Id(), agent.UserId(), e); err != nil {
		wlog.Error(err.Error())
	}
}

func (tm *agentTeam) Offering(attempt *Attempt, agent agent_manager.AgentObject, aChannel, mChannel Channel) {
	agentId := model.NewInt(agent.Id())
	agentCallId := model.NewString(aChannel.Id())
	var mCallId *string = nil
	if mChannel != nil {
		mCallId = model.NewString(mChannel.Id())
	}

	timestamp, err := tm.teamManager.store.Member().SetAttemptOffering(attempt.Id(), agentId, agentCallId, mCallId, &attempt.communication.Destination, attempt.communication.Display)
	if err != nil {
		wlog.Error(err.Error())
		return
	}
	attempt.SetState(model.MemberStateOffering)
	e := NewOfferingEvent(attempt, agent.UserId(), timestamp, aChannel, mChannel)
	err = tm.teamManager.mq.AgentChannelEvent(attempt.channel, attempt.domainId, attempt.QueueId(), agent.UserId(), e)
	if err != nil {
		wlog.Error(err.Error())
		return
	}
}

// TODO!!!!! ADD FAILED
func (tm *agentTeam) Cancel(attempt *Attempt, agent agent_manager.AgentObject) {

	if _, ok := attempt.AfterDistributeSchema(); ok {
		//TODO
	}

	res, err := tm.teamManager.store.Member().SetAttemptAbandonedWithParams(attempt.Id(),
		attempt.maxAttempts, attempt.waitBetween, nil, attempt.perNumbers, attempt.excludeCurrNumber, attempt.redial,
		attempt.description, attempt.stickyAgentId)
	if err != nil {
		wlog.Error(err.Error())

		return
	}

	if res.MemberStopCause != nil {
		attempt.SetMemberStopCause(res.MemberStopCause)
	}

	attId := model.NewInt64(attempt.Id())
	e := NewWaitingChannelEvent(attempt.channel, agent.UserId(), attId, res.Timestamp)
	err = tm.teamManager.mq.AgentChannelEvent(attempt.channel, attempt.domainId, attempt.QueueId(), agent.UserId(), e)
	if err != nil {
		wlog.Error(err.Error())
	}
}

func (queue *BaseQueue) RingtoneUri() string {
	if queue.ringtoneUri != nil {
		return *queue.ringtoneUri
	}

	return ""
}

func (queue *BaseQueue) AmdPlaybackUri() *string {
	return queue.amdPlaybackFileUri
}
