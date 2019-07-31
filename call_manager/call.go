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
	State() <-chan uint8

	HangupCause() string
	GetState() uint8
	Err() *model.AppError
	GetAttribute(name string) (string, bool)
	GetIntAttribute(name string) (int, bool)

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
	Hangup(cause string) *model.AppError
	Hold() *model.AppError
	DTMF(val rune) *model.AppError
	Bridge(other Call) *model.AppError
}

type CallImpl struct {
	callRequest *model.CallRequest
	api         model.CallCommands
	direction   CallDirection
	cm          *CallManagerImpl
	id          string
	hangupCause string
	hangup      chan struct{}
	lastEvent   *CallEvent
	err         *model.AppError
	state       uint8

	chState chan uint8

	offeringAt int64
	acceptAt   int64
	bridgeAt   int64
	hangupAt   int64

	sync.RWMutex
}

type CallDirection string

const (
	CALL_STATE_NEW = iota
	CALL_STATE_RINGING
	CALL_STATE_ACCEPT
	CALL_STATE_BRIDGE
	CALL_STATE_PARK
	CALL_STATE_HANGUP

	CALL_DIRECTION_INBOUND  = "inbound"
	CALL_DIRECTION_OUTBOUND = "outbound"
)

var (
	errBadBridgeNode   = model.NewAppError("Call", "call.bridge.bad_request.node_difference", nil, "", http.StatusBadRequest)
	errInviteDirection = model.NewAppError("Call", "call.invite.validate.direction", nil, "", http.StatusBadRequest)
)

func NewCall(direction CallDirection, callRequest *model.CallRequest, cm *CallManagerImpl, api model.CallCommands) Call {
	id := model.NewUuid()
	callRequest.Variables[model.CALL_ORIGINATION_UUID] = id
	callRequest.Variables[model.QUEUE_NODE_ID_FIELD] = cm.nodeId

	call := &CallImpl{
		callRequest: callRequest,
		direction:   direction,
		id:          id,
		api:         api,
		cm:          cm,
		hangup:      make(chan struct{}),
		chState:     make(chan uint8),
		state:       CALL_STATE_NEW,
	}

	wlog.Debug(fmt.Sprintf("[%s] call %s init request", call.NodeName(), call.Id()))

	return call
}

func (cm *CallManagerImpl) newInboundCall(fromNode string, event *CallEvent) *model.AppError {
	api, err := cm.pool.getByName(fromNode)

	if err != nil {
		return err
	}

	call := &CallImpl{
		id:        event.Id(),
		api:       api,
		cm:        cm,
		direction: CALL_DIRECTION_INBOUND,
		hangup:    make(chan struct{}),
		lastEvent: event,
		chState:   make(chan uint8, 5),
		state:     CALL_STATE_ACCEPT,
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

func (call *CallImpl) setState(event *CallEvent, state uint8) {
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
	call.state = state
	call.Unlock()

	call.chState <- state
	wlog.Debug(fmt.Sprintf("[%s] call %s set state  %d", call.NodeName(), call.Id(), state))
}

func (call *CallImpl) State() <-chan uint8 {
	return call.chState
}

func (call *CallImpl) GetState() uint8 {
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

func (call *CallImpl) WaitForHangup() {
	if call.Err() == nil && call.HangupCause() == "" {
		for {
			select {
			case <-call.HangupChan():
				return
			case <-call.chState:

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
	return call.intVarIfLastEvent("duration")
}

func (call *CallImpl) BillSeconds() int {
	return call.intVarIfLastEvent("billsec")
}

func (call *CallImpl) AnswerSeconds() int {
	return call.intVarIfLastEvent("answersec")
}

func (call *CallImpl) WaitSeconds() int {
	return call.intVarIfLastEvent("waitsec")
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
	}

	if call.hangupCause == "" {
		call.hangupCause = cause
		wlog.Debug(fmt.Sprintf("[%s] call %s set hangup cause %s", call.NodeName(), call.Id(), cause))
	}
}

func (call *CallImpl) Err() *model.AppError {
	call.RLock()
	defer call.RUnlock()

	return call.err
}

func (call *CallImpl) Hangup(cause string) *model.AppError {
	wlog.Debug(fmt.Sprintf("[%s] call %s send hangup %s", call.NodeName(), call.Id(), cause))
	return call.api.HangupCall(call.id, cause)
}

func (call *CallImpl) Mute(on bool) *model.AppError {
	/*
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
