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
	processing           bool
	processingSec        uint32
	processingRenewalSec uint32
	hooks                HookHub
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
		processing:           settings.Processing,
		processingSec:        settings.ProcessingSec,
		processingRenewalSec: settings.ProcessingRenewalSec,
		hooks:                NewHookHub(settings.Hooks),
	}

	if settings.RingtoneId != nil && settings.RingtoneType != nil {
		base.ringtone = &model.RingtoneFile{
			Id:   *settings.RingtoneId,
			Type: *settings.RingtoneType,
		}
		base.ringtoneUri = model.NewString(model.RingtoneUri(base.domainId, base.ringtone.Id, base.ringtone.Type))
	}

	if settings.GranteeId != nil {
		base.variables["wbt_grantee_id"] = fmt.Sprintf("%d", *settings.GranteeId)
	}

	return base
}

func NewQueue(queueManager *QueueManager, resourceManager *ResourceManager, settings *model.Queue) (QueueObject, *model.AppError) {
	base := NewBaseQueue(queueManager, resourceManager, settings)

	switch settings.Type {
	case model.QUEUE_TYPE_OFFLINE:
		return NewOfflineCallQueue(CallingQueue{
			BaseQueue: base,
		}, QueueOfflineSettingsFromBytes(settings.Payload)), nil
	case model.QUEUE_TYPE_INBOUND:
		inboundSettings := model.QueueInboundSettingsFromBytes(settings.Payload)
		return NewInboundQueue(CallingQueue{
			BaseQueue: base,
		}, inboundSettings), nil

	case model.QUEUE_TYPE_IVR:
		return NewIVRQueue(CallingQueue{
			BaseQueue: base,
		}, QueueIVRSettingsFromBytes(settings.Payload)), nil

	case model.QUEUE_TYPE_PREVIEW:
		return NewPreviewCallQueue(CallingQueue{
			BaseQueue: base,
		}, PreviewSettingsFromBytes(settings.Payload)), nil

	case model.QUEUE_TYPE_PROGRESSIVE:
		return NewProgressiveCallQueue(CallingQueue{
			BaseQueue: base,
		}, ProgressiveSettingsFromBytes(settings.Payload)), nil

	case model.QUEUE_TYPE_PREDICT:
		return NewPredictCallQueue(CallingQueue{
			BaseQueue: base,
		}, PredictCallQueueSettingsFromBytes(settings.Payload)), nil

	case model.QueueTypeChat:
		return NewInboundChatQueue(base, InboundChatQueueFromBytes(settings.Payload)), nil
	case model.QueueTypeAgentTask:
		return NewTaskAgentQueue(base), nil

	default:
		return nil, model.NewAppError("Dialing.NewQueue", "dialing.queue.new_queue.app_error", nil,
			fmt.Sprintf("Queue type %v not implement", settings.Type), http.StatusInternalServerError)
	}
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
	if queue.teamId != nil && attempt.TeamUpdatedAt() != nil {
		return queue.TeamManager().GetTeam(*queue.teamId, *attempt.TeamUpdatedAt())
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
	case model.QUEUE_TYPE_OFFLINE:
		return "offline"
	case model.QUEUE_TYPE_INBOUND:
		return "inbound"
	case model.QUEUE_TYPE_IVR:
		return "ivr"
	case model.QUEUE_TYPE_PREVIEW:
		return "preview"
	case model.QUEUE_TYPE_PROGRESSIVE:
		return "progressive"
	case model.QUEUE_TYPE_PREDICT:
		return "predictive"
	case model.QueueTypeChat:
		return "inbound chat"
	case model.QueueTypeAgentTask:
		return "task"
	default:
		return "NOT_IMPLEMENT"
	}
}

func (queue *BaseQueue) Variables() map[string]string {
	return queue.variables
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

func (tm *agentTeam) Cancel(attempt *Attempt, agent agent_manager.AgentObject, maxAttempts uint, sleep uint64) {
	//SetAttemptAbandonedWithParams
	//timestamp, err := tm.teamManager.store.Member().SetAttemptAbandoned(attempt.Id())
	res, err := tm.teamManager.store.Member().SetAttemptAbandonedWithParams(attempt.Id(), maxAttempts, sleep, nil)
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
