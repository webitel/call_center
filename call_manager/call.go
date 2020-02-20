package call_manager

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
	"net/http"
	"sync"
)

type Call interface {
	Id() string
	NodeName() string

	FromNumber() string
	FromName() string

	Invite() *model.AppError
	State() <-chan CallState

	HangupCause() string
	HangupCauseCode() int
	GetState() CallState
	Err() *model.AppError
	GetAttribute(name string) (string, bool)
	GetIntAttribute(name string) (int, bool)

	CallAction() <-chan CallAction
	AddAction(action CallAction)

	OfferingAt() int64
	AcceptAt() int64
	BridgeAt() int64
	HangupAt() int64

	DurationSeconds() int
	BillSeconds() int
	AnswerSeconds() int
	WaitSeconds() int

	WaitForHangup()
	HangupChan() <-chan struct{}

	NewCall(callRequest *model.CallRequest) Call
	ExecuteApplications(apps []*model.CallRequestApplication) *model.AppError
	Hangup(cause string) *model.AppError
	Hold() *model.AppError
	DTMF(val rune) *model.AppError
	Bridge(other Call) *model.AppError
}

type CallAction struct {
	Action string
	Data   map[string]string
}

const (
	CALL_ACTION_DIAL     = "dial"
	CALL_ACTION_JOIN     = "join"
	CALL_ACTION_CANCEL   = "cancel"
	CALL_ACTION_TRANSFER = "transfer"
)

type CallImpl struct {
	callRequest     *model.CallRequest
	api             model.CallCommands
	direction       CallDirection
	cm              *CallManagerImpl
	actions         chan CallAction
	id              string
	hangupCause     string
	hangupCauseCode int
	hangup          chan struct{}
	lastEvent       *CallEvent
	err             *model.AppError
	state           CallState
	cancel          string

	chState chan CallState

	offeringAt int64
	acceptAt   int64
	bridgeAt   int64
	hangupAt   int64

	sync.RWMutex
}

type CallDirection string
type CallState uint8

const (
	CALL_STATE_NEW CallState = iota
	CALL_STATE_INVITE
	CALL_STATE_RINGING
	CALL_STATE_ACCEPT
	CALL_STATE_BRIDGE
	CALL_STATE_PARK
	CALL_STATE_HANGUP
)

const (
	CALL_DIRECTION_INBOUND  CallDirection = "inbound"
	CALL_DIRECTION_OUTBOUND               = "outbound"
)

func (s CallState) String() string {
	return [...]string{"new", "invite", "ringing", "accept", "bridge", "park", "hangup"}[s]
}

var (
	errBadBridgeNode   = model.NewAppError("Call", "call.bridge.bad_request.node_difference", nil, "", http.StatusBadRequest)
	errInviteDirection = model.NewAppError("Call", "call.invite.validate.direction", nil, "", http.StatusBadRequest)
)

func NewCall(direction CallDirection, callRequest *model.CallRequest, cm *CallManagerImpl, api model.CallCommands) Call {
	id := model.NewUuid()
	callRequest.Variables[model.CALL_ORIGINATION_UUID] = id
	callRequest.Variables[model.QUEUE_NODE_ID_FIELD] = cm.nodeId
	callRequest.Variables[model.CALL_PROXY_URI_VARIABLE] = cm.Proxy()

	call := &CallImpl{
		callRequest: callRequest,
		direction:   direction,
		id:          id,
		api:         api,
		cm:          cm,
		hangup:      make(chan struct{}),
		chState:     make(chan CallState, 5),
		actions:     make(chan CallAction, 5), //FIXME
		state:       CALL_STATE_NEW,
	}

	wlog.Debug(fmt.Sprintf("[%s] call %s init request", call.NodeName(), call.Id()))

	return call
}

func (call *CallImpl) CallAction() <-chan CallAction {
	return call.actions
}

func (call *CallImpl) AddAction(action CallAction) {
	call.actions <- action
}

func (cm *CallManagerImpl) Proxy() string {
	return "sip:10.9.8.111:5060"
}

func (cm *CallManagerImpl) newInboundCall(fromNode string, event *CallEvent) *model.AppError {
	api, err := cm.getApiConnectionById(fromNode)

	if err != nil {
		return err
	}

	createdAt, _ := event.GetIntAttribute(CallerCreatedTimeHeader)
	if createdAt > 0 {
		createdAt = createdAt / 1000
	}

	answeredTime, _ := event.GetIntAttribute(CallerAnsweredTimeHeader)
	if answeredTime > 0 {
		answeredTime = answeredTime / 1000
	}

	call := &CallImpl{
		id:         event.Id(),
		api:        api,
		cm:         cm,
		direction:  CALL_DIRECTION_INBOUND,
		hangup:     make(chan struct{}),
		lastEvent:  event,
		chState:    make(chan CallState, 5),
		acceptAt:   int64(answeredTime),
		offeringAt: int64(createdAt),
		state:      CALL_STATE_ACCEPT,
	}

	cm.saveToCacheCall(call)
	cm.inboundCall <- call

	return nil
}

func (call *CallImpl) Invite() *model.AppError {
	call.cm.saveToCacheCall(call)

	if call.direction != CALL_DIRECTION_OUTBOUND {
		return errInviteDirection
	}

	call.state = CALL_STATE_INVITE

	wlog.Debug(fmt.Sprintf("[%s] call %s send invite", call.NodeName(), call.Id()))

	go func() {
		_, cause, err := call.api.NewCall(call.callRequest)
		if err != nil {
			wlog.Debug(fmt.Sprintf("[%s] call %s invite error: %s", call.NodeName(), call.Id(), err.Error()))
			call.setHangupCall(err, nil, cause)
			return
		}
	}()

	return nil
}

func (call *CallImpl) setHangupCode() {
	if call.lastEvent != nil {
		call.hangupCauseCode, _ = call.lastEvent.GetIntAttribute(model.CALL_ATTRIBUTE_HANGUP_CODE)
	}
}

func (c *CallImpl) NewCall(callRequest *model.CallRequest) Call {
	return NewCall(CALL_DIRECTION_OUTBOUND, callRequest, c.cm, c.api)
}

func (call *CallImpl) FromNumber() string {
	if call.lastEvent != nil {
		v, _ := call.lastEvent.GetStrAttribute(model.CALL_ATTRIBUTE_FROM_NUMBER)
		return v
	}
	return ""
}

func (call *CallImpl) FromName() string {
	if call.lastEvent != nil {
		v, _ := call.lastEvent.GetStrAttribute(model.CALL_ATTRIBUTE_FROM_NAME)
		return v
	}
	return ""
}

func (call *CallImpl) NodeName() string {
	return call.api.Name()
}

func (call *CallImpl) setState(event *CallEvent, state CallState) {
	call.Lock()
	switch state {
	case CALL_STATE_RINGING:
		call.offeringAt = model.GetMillis()
	case CALL_STATE_ACCEPT:
		call.acceptAt = model.GetMillis()
	case CALL_STATE_BRIDGE:
		call.bridgeAt = model.GetMillis()
	case CALL_STATE_HANGUP:
		call.hangupAt = model.GetMillis()
	}

	if event != nil {
		call.lastEvent = event
	}
	//FIXME handle error
	if call.cancel != "" && state < CALL_STATE_HANGUP {
		if err := call.api.HangupCall(call.Id(), call.cancel); err != nil {
			wlog.Error(fmt.Sprintf("[%s] call %s error: \"%s\"", call.NodeName(), call.Id(), err.Error()))
		}
		wlog.Debug(fmt.Sprintf("[%s] call %s send hangup \"%s\"", call.NodeName(), call.Id(), call.cancel))
		call.cancel = ""
	}

	call.state = state

	call.Unlock()

	call.chState <- state
	wlog.Debug(fmt.Sprintf("[%s] call %s set state \"%s\"", call.NodeName(), call.Id(), state.String()))
}

func (call *CallImpl) State() <-chan CallState {
	return call.chState
}

func (call *CallImpl) GetState() CallState {
	call.RLock()
	defer call.RUnlock()
	return call.state
}

func (call *CallImpl) Id() string {
	return call.id
}

func (call *CallImpl) HangupCause() string {
	call.RLock()
	defer call.RUnlock()
	return call.hangupCause
}

func (call *CallImpl) HangupCauseCode() int {
	call.RLock()
	defer call.RUnlock()
	return call.hangupCauseCode
}

func (call *CallImpl) WaitForHangup() {
	if call.Err() == nil && call.HangupCause() == "" {
		for {
			select {
			case <-call.HangupChan():
				return
			}
		}
	}
}

func (call *CallImpl) HangupChan() <-chan struct{} {
	return call.hangup
}

func (call *CallImpl) OfferingAt() int64 {
	return call.offeringAt
}

func (call *CallImpl) AcceptAt() int64 {
	return call.acceptAt
}

func (call *CallImpl) BridgeAt() int64 {
	return call.bridgeAt
}

func (call *CallImpl) HangupAt() int64 {
	return call.hangupAt
}

func (call *CallImpl) intVarIfLastEvent(name string) int {
	if call.lastEvent == nil {
		return 0
	}
	v, _ := call.lastEvent.GetIntAttribute(name)
	return v
}

func (call *CallImpl) DurationSeconds() int {
	if call.hangupAt > 0 {
		return int(call.hangupAt-call.offeringAt) / 1000
	} else {
		return int(model.GetMillis()-call.offeringAt) / 1000
	}
}

func (call *CallImpl) BillSeconds() int {
	if call.bridgeAt > 0 {
		if call.hangupAt > 0 {
			return int(call.hangupAt-call.bridgeAt) / 1000
		} else {
			return int(model.GetMillis()-call.bridgeAt) / 1000
		}
	}
	return 0
}

func (call *CallImpl) AnswerSeconds() int {
	if call.acceptAt > 0 {
		return int(call.acceptAt-call.offeringAt) / 1000
	} else {
		return 0
	}
}

func (call *CallImpl) WaitSeconds() int {
	if call.bridgeAt > 0 {
		return int(call.bridgeAt-call.offeringAt) / 1000
	} else {
		return int(model.GetMillis()-call.offeringAt) / 1000
	}
}

func (call *CallImpl) setHangupCall(err *model.AppError, event *CallEvent, cause string) {
	if call.GetState() < CALL_STATE_HANGUP {
		call.setHangupCause(err, cause)
		call.cm.removeFromCacheCall(call)
		call.setState(event, CALL_STATE_HANGUP)
		close(call.hangup)
	}
}

func (call *CallImpl) setHangupCause(err *model.AppError, cause string) {
	call.Lock()
	defer call.Unlock()

	if err != nil {
		call.err = err
		call.hangupCauseCode = err.StatusCode
	} else {
		call.setHangupCode()
	}

	if call.hangupCause == "" {
		call.hangupCause = cause
		wlog.Debug(fmt.Sprintf("[%s] call %s set hangup cause: %s code: %d", call.NodeName(), call.Id(), cause, call.hangupCauseCode))
	}
}

func (call *CallImpl) Err() *model.AppError {
	call.RLock()
	defer call.RUnlock()

	return call.err
}

func (call *CallImpl) Hangup(cause string) *model.AppError {
	if call.GetState() < CALL_STATE_RINGING {
		wlog.Debug(fmt.Sprintf("[%s] call %s set cancel %s", call.NodeName(), call.Id(), cause))
		call.setCancel(cause)
		if call.GetState() == CALL_STATE_NEW {
			close(call.hangup)
		}
		return nil
	}

	wlog.Debug(fmt.Sprintf("[%s] call %s send hangup %s", call.NodeName(), call.Id(), cause))
	return call.api.HangupCall(call.id, cause)
}

func (call *CallImpl) ExecuteApplications(apps []*model.CallRequestApplication) *model.AppError {
	return call.api.ExecuteApplications(call.id, apps)
}

func (call *CallImpl) setCancel(cause string) {
	call.Lock()
	defer call.Unlock()
	call.cancel = cause
}

func (call *CallImpl) Cancel() string {
	call.RLock()
	defer call.RUnlock()
	return call.cancel
}

func (call *CallImpl) Mute(on bool) *model.AppError {
	/*
		uuid_audio 8e345bfc-47b9-46c1-bdf0-3b874a8539c8 start read mute -1
			uuid_audio
			Adjust the audio levels on a channel or mute (read/write) via a media bug.

			Usage: uuid_audio <uuid> [start [read|write] [[mute|level] <level>]|stop]
			<level> is in the range from -4 to 4, 0 being the default value.

			Level is required for both mute|level params:

			freeswitch@internal> uuid_audio 0d7c3b93-a5ae-4964-9e4d-902bba50bd19 start write mute <level>
			freeswitch@internal> uuid_audio 0d7c3b93-a5ae-4964-9e4d-902bba50bd19 start write level <level>

	*/

	return nil
}

func (call *CallImpl) Hold() *model.AppError {
	return call.api.Hold(call.id)
}

func (call *CallImpl) Bridge(other Call) *model.AppError {
	if call.NodeName() != other.NodeName() {
		return errBadBridgeNode
	}

	_, err := call.api.BridgeCall(other.Id(), call.Id(), "")

	if err == nil {
		call.bridgeAt = model.GetMillis()
	}

	return err
}

func (call *CallImpl) DTMF(val rune) *model.AppError {
	return call.api.DTMF(call.id, val)
}

func (call *CallImpl) GetAttribute(name string) (string, bool) {
	if call.lastEvent != nil {
		return call.lastEvent.GetVariable(name)
	}
	return "", false
}

func (call *CallImpl) GetIntAttribute(name string) (int, bool) {
	if call.lastEvent != nil {
		return call.lastEvent.GetIntAttribute("variable_" + name)
	}
	return 0, false
}
