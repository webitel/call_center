package call_manager

import (
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
)

type CallImpl struct {
	callRequest *model.CallRequest
	api         model.CallCommands
	id          string
	hangupCause string
	hangup      chan struct{}
	lastEvent   mq.Event
	err         *model.AppError
}

func NewCall(callRequest *model.CallRequest, api model.CallCommands) Call {
	call := &CallImpl{
		callRequest: callRequest,
		api:         api,
		hangup:      make(chan struct{}),
	}
	call.id, call.hangupCause, call.err = call.api.NewCall(call.callRequest)

	return call
}

func (call *CallImpl) Id() string {
	return call.id
}

func (call *CallImpl) HangupCause() string {
	return call.hangupCause
}

func (call *CallImpl) WaitHangup() {
	if call.err == nil && call.hangupCause == "" {
		<-call.hangup
	}
}

func (call *CallImpl) SetHangupCall(event mq.Event) {
	call.lastEvent = event
	call.hangupCause, _ = event.GetVariable(model.CALL_HANGUP_CAUSE_VARIABLE)
	close(call.hangup)
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

func (call *CallImpl) UseAMD() *model.AppError {
	return nil
}

func (call *CallImpl) RecordSession() *model.AppError {
	return nil
}
