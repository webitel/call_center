package call_manager

import (
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
	"net/http"
	"sync"
)

type CallImpl struct {
	callRequest *model.CallRequest
	api         model.CallCommands
	cm          *CallManagerImpl
	id          string
	hangupCause string
	hangup      chan struct{}
	lastEvent   mq.Event
	err         *model.AppError
	state       uint8

	offeringAt int64
	acceptAt   int64
	bridgeAt   int64
	hangupAt   int64

	sync.RWMutex
}

const (
	CALL_STATE_RINGING = iota
	CALL_STATE_ACCEPT
	CALL_STATE_BRIDGE
	CALL_STATE_PARK
	CALL_STATE_HANGUP
)

var (
	errBadBridgeNode = model.NewAppError("Call", "call.bridge.bad_request.node_difference", nil, "", http.StatusBadRequest)
)

func NewCall(callRequest *model.CallRequest, cm *CallManagerImpl, api model.CallCommands) Call {
	id := model.NewId()
	callRequest.Variables[model.CALL_ID] = id
	callRequest.Variables[model.QUEUE_NODE_ID_FIELD] = cm.nodeId

	call := &CallImpl{
		callRequest: callRequest,
		api:         api,
		cm:          cm,
		hangup:      make(chan struct{}),
	}
	cm.SetCall(id, call)
	call.setState(CALL_STATE_RINGING)
	call.id, call.hangupCause, call.err = call.api.NewCall(call.callRequest)
	if call.err != nil {
		cm.RemoveCall(id)
	}
	call.setState(CALL_STATE_ACCEPT)
	return call
}

func (c *CallImpl) NewCall(callRequest *model.CallRequest) Call {
	return NewCall(callRequest, c.cm, c.api)
}

func (call *CallImpl) NodeName() string {
	return call.api.Name()
}

func (call *CallImpl) setState(state uint8) {
	call.Lock()
	defer call.Unlock()
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
	call.state = state
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
	return call.hangupCause
}

func (call *CallImpl) WaitForHangup() {
	if call.err == nil && call.hangupCause == "" {
		<-call.hangup
	}
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
	v, _ := call.lastEvent.GetIntVariable(name)
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

func (call *CallImpl) SetHangupCall(event mq.Event) {
	if call.GetState() < CALL_STATE_HANGUP {
		call.setState(CALL_STATE_HANGUP)
		call.lastEvent = event
		call.hangupCause, _ = event.GetVariable(model.CALL_HANGUP_CAUSE_VARIABLE)
		close(call.hangup)
	}
}

func (call *CallImpl) Err() *model.AppError {
	return call.err
}

func (call *CallImpl) Hangup(cause string) *model.AppError {
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
