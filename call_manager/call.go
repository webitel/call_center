package call_manager

import (
	"context"
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

	Direction() CallDirection

	QueueId() *int
	QueueCallPriority() int

	Invite() *model.AppError
	State() <-chan CallState

	HangupCause() string
	HangupCauseCode() int
	GetState() CallState
	Err() *model.AppError

	CallAction() <-chan CallAction
	AddAction(action CallAction)

	BridgeId() *string
	Answered() bool

	AcceptAt() int64
	BridgeAt() int64
	HangupAt() int64
	ReportingAt() int64

	Transferred() bool
	TransferTo() *string
	TransferFrom() *string
	TransferToAgentId() *int
	TransferFromAttemptId() *int64
	TransferToAttemptId() *int64

	DurationSeconds() int
	BillSeconds() int
	AnswerSeconds() int
	WaitSeconds() int

	AmdResult() string
	IsHuman() bool

	WaitForHangup()
	HangupChan() <-chan struct{}

	NewCall(callRequest *model.CallRequest) Call
	//ExecuteApplications(apps []*model.CallRequestApplication) *model.AppError
	Hangup(cause string, reporting bool, vars map[string]string) *model.AppError
	Hold() *model.AppError
	DTMF(val rune) *model.AppError
	Bridge(other Call) *model.AppError
	BroadcastPlaybackFile(domainId int64, file *model.RingtoneFile, leg string) *model.AppError
	ParkPlaybackFile(domainId int64, file *model.RingtoneFile, leg string) *model.AppError
	BroadcastTone(tone *string, leg string) *model.AppError
	BroadcastPlaybackSilenceBeforeFile(domainId int64, silence uint, file *model.RingtoneFile, leg string) *model.AppError
	StopPlayback() *model.AppError
	SerVariables(vars map[string]string) *model.AppError

	SetRecordings(domainId int64, all, mono bool)
	UpdateCid() *model.AppError
	ResetBridge()

	Stats() map[string]string
	SetOtherChannelVar(vars map[string]string) *model.AppError
	AiResult() model.AmdAiResult
}

type CallAction struct {
	Action string
	Data   map[string]string
}

type CallImpl struct {
	callRequest *model.CallRequest
	api         model.CallCommands
	direction   CallDirection
	cm          *CallManagerImpl
	actions     chan CallAction
	id          string
	hangupCh    chan struct{}
	state       CallState
	cancel      string

	chState chan CallState

	info   model.CallActionInfo
	hangup *model.CallActionHangup
	action model.CallAction

	bridgedId *string

	ringingAt   int64
	acceptAt    int64
	bridgeAt    int64
	hangupAt    int64
	reportingAt int64

	transferTo            *string
	transferFrom          *string
	transferToAgentId     *int
	transferFromAttemptId *int64
	transferToAttemptId   *int64

	queueId *int //FIXME

	amdResult string
	amdCause  string

	amdAiResult model.AmdAiResult

	variables map[string]interface{}

	sync.RWMutex
}

type CallDirection string
type CallState uint8

const (
	CALL_STATE_NEW CallState = iota
	CALL_STATE_INVITE
	CALL_STATE_RINGING
	CALL_STATE_ACCEPT
	CALL_STATE_JOIN
	CALL_STATE_LEAVING
	CALL_STATE_BRIDGE
	CALL_STATE_HOLD
	CALL_STATE_DETECT_AMD
	CALL_STATE_HANGUP
)

const (
	CALL_DIRECTION_INBOUND  CallDirection = "inbound"
	CALL_DIRECTION_OUTBOUND               = "outbound"
)

const (
	AmdHuman   = "HUMAN"
	AmdNotSure = "NOTSURE"
)

func (s CallState) String() string {
	return [...]string{"new", "invite", "ringing", "accept", "join", "leaving", "bridge", "hold", "amd", "hangup"}[s]
}

var (
	errBadBridgeNode   = model.NewAppError("Call", "call.bridge.bad_request.node_difference", nil, "", http.StatusBadRequest)
	errInviteDirection = model.NewAppError("Call", "call.invite.validate.direction", nil, "", http.StatusBadRequest)
)

func NewCall(direction CallDirection, callRequest *model.CallRequest, cm *CallManagerImpl, api model.CallCommands) Call {
	var id string
	if callRequest.Id != nil {
		id = *callRequest.Id
	} else {
		id = model.NewUuid()
	}

	if callRequest.Variables == nil {
		callRequest.Variables = make(map[string]string)
	}
	callRequest.Variables[model.CALL_ORIGINATION_UUID] = id
	callRequest.Variables[model.QUEUE_NODE_ID_FIELD] = cm.nodeId
	callRequest.Variables[model.CALL_PROXY_URI_VARIABLE] = cm.Proxy()
	callRequest.Variables["sip_copy_custom_headers"] = "false"

	//DUMP(callRequest)

	call := &CallImpl{
		callRequest: callRequest,
		direction:   direction,
		id:          id,
		api:         api,
		cm:          cm,
		hangupCh:    make(chan struct{}),
		chState:     make(chan CallState, 5), // FIXME
		state:       CALL_STATE_NEW,
	}

	wlog.Debug(fmt.Sprintf("[%s] call %s init request", call.NodeName(), call.Id()))

	return call
}

func (call *CallImpl) SetRecordings(domainId int64, all, mono bool) {

	call.callRequest.Variables["RECORD_MIN_SEC"] = "2"
	call.callRequest.Variables["recording_follow_transfer"] = "true"

	if all {
		call.callRequest.Variables["RECORD_BRIDGE_REQ"] = "false"
		call.callRequest.Variables["media_bug_answer_req"] = "false"
	} else {
		call.callRequest.Variables["RECORD_BRIDGE_REQ"] = "true"
		call.callRequest.Variables["media_bug_answer_req"] = "true"
	}

	if mono {
		call.callRequest.Variables["RECORD_STEREO"] = "false"
	} else {
		call.callRequest.Variables["RECORD_STEREO"] = "true"
	}

	call.callRequest.Applications = append(call.callRequest.Applications, &model.CallRequestApplication{
		AppName: "record_session",
		Args: fmt.Sprintf("http_cache://http://$${cdr_url}/sys/recordings?domain=%d&id=%s&name=%s_%s&.%s", domainId,
			call.Id(), call.Id(), model.CallRecordFileTemplate, "mp3"),
	})
}

func (call *CallImpl) Direction() CallDirection {
	return call.direction
}

func (call *CallImpl) setRinging(e *model.CallActionRinging) {
	call.Lock()
	call.info = e.CallActionInfo
	call.ringingAt = e.Timestamp
	call.Unlock()

	call.setState(CALL_STATE_RINGING)
}

func (call *CallImpl) setActive(e *model.CallActionActive) {
	if call.acceptAt == 0 {
		call.Lock()
		call.acceptAt = e.Timestamp
		call.Unlock()

		call.setState(CALL_STATE_ACCEPT)
	} else {
		//FIXME Unhold
	}
}

func (call *CallImpl) setBridge(e *model.CallActionBridge) {
	call.Lock()
	call.bridgeAt = e.Timestamp
	call.bridgedId = model.NewString(e.BridgedId)
	call.Unlock()

	call.setState(CALL_STATE_BRIDGE)
}

func (call *CallImpl) setAmd(e *model.CallActionAMD) {
	call.Lock()
	call.amdResult = e.Result
	call.amdCause = e.Cause

	call.amdAiResult = e.AmdAiResult

	call.Unlock()

	call.setState(CALL_STATE_DETECT_AMD)
}

func (call *CallImpl) AiResult() model.AmdAiResult {
	call.RLock()
	res := call.amdAiResult
	call.RUnlock()

	return res
}

func (call *CallImpl) StopPlayback() *model.AppError {
	return call.api.StopPlayback(call.id)
}

func (call *CallImpl) AmdResult() string {
	call.RLock()
	defer call.RUnlock()
	return call.amdResult
}

func (call *CallImpl) BridgeId() *string {
	call.RLock()
	defer call.RUnlock()
	return call.bridgedId
}

func (call *CallImpl) setHold(e *model.CallActionHold) {
	call.setState(CALL_STATE_HOLD)
}

func (call *CallImpl) setHangup(e *model.CallActionHangup) {
	call.Lock()
	if call.hangupAt == 0 {
		call.hangup = e
		call.cm.removeFromCacheCall(call)
		call.hangupAt = e.Timestamp
		if call.hangupAt == 0 {
			wlog.Warn(fmt.Sprintf("call %s set server hangup time", call.Id()))
			call.hangupAt = model.GetMillis()
		}

		if e.ReportingAt != nil {
			call.reportingAt = *e.ReportingAt
		}

		call.transferFrom = e.TransferFrom
		call.transferFromAttemptId = e.TransferFromAttempt
		call.transferTo = e.TransferTo
		call.transferToAgentId = e.TransferToAgent
		call.transferToAttemptId = e.TransferToAttempt

		call.variables = e.Variables

		close(call.hangupCh)
		call.Unlock()

		call.setState(CALL_STATE_HANGUP)
	} else {
		call.Unlock()
	}

}

func (call *CallImpl) QueueId() *int {
	return call.queueId
}

func (call *CallImpl) QueueCallPriority() int {
	//fixme
	return 0
}

func (call *CallImpl) CallAction() <-chan CallAction {
	return call.actions
}

func (call *CallImpl) AddAction(action CallAction) {
	call.actions <- action
}

func (cm *CallManagerImpl) Proxy() string {
	return "sip:" + cm.proxy
}

func (call *CallImpl) Invite() *model.AppError {
	call.cm.saveToCacheCall(call)
	//DUMP(call.callRequest)

	if call.direction != CALL_DIRECTION_OUTBOUND {
		return errInviteDirection
	}

	call.state = CALL_STATE_INVITE

	wlog.Debug(fmt.Sprintf("[%s] call %s send invite", call.NodeName(), call.Id()))

	go func() {
		_, cause, code, err := call.api.NewCall(call.callRequest)
		if err != nil {
			wlog.Debug(fmt.Sprintf("[%s] call %s invite error: %s", call.NodeName(), call.Id(), err.Error()))
			call.setHangup(&model.CallActionHangup{
				CallAction: call.action,
				Cause:      cause,
				SipCode:    &code,
			})
			return
		}
	}()

	return nil
}

func (c *CallImpl) NewCall(callRequest *model.CallRequest) Call {
	//TODO added parent
	return NewCall(CALL_DIRECTION_OUTBOUND, callRequest, c.cm, c.api)
}

func (call *CallImpl) FromNumber() string {
	if call.info.From != nil {
		return call.info.From.Number
	}
	return ""
}

func (call *CallImpl) FromName() string {
	if call.info.From != nil {
		return call.info.From.Name
	}
	return ""
}

// FIXME PLEASE
func (call *CallImpl) NodeName() string {
	// FIXME крешиться коли сфвіч падає
	return call.api.Name()
}

func (call *CallImpl) setState(state CallState) {
	call.state = state
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
	if call.hangup != nil {
		return call.hangup.Cause
	}

	return ""
}

func (call *CallImpl) HangupCauseCode() int {
	call.RLock()
	defer call.RUnlock()
	if call.hangup != nil && call.hangup.SipCode != nil {
		return *call.hangup.SipCode
	}
	//FIXME
	return 0
}

func (call *CallImpl) Variables() map[string]interface{} {
	call.RLock()
	defer call.RUnlock()

	return call.variables
}

func (call *CallImpl) WaitForHangup() {
	if call.Err() == nil && call.HangupCause() == "" {
		<-call.HangupChan()
	}
}

func (call *CallImpl) HangupChan() <-chan struct{} {
	return call.hangupCh
}

func (call *CallImpl) ReportingAt() int64 {
	return call.reportingAt
}

func (call *CallImpl) Transferred() bool {
	call.RLock()
	defer call.RUnlock()

	return call.transferTo != nil
}

func (call *CallImpl) TransferTo() *string {
	call.RLock()
	defer call.RUnlock()

	return call.transferTo
}

func (call *CallImpl) TransferFrom() *string {
	call.RLock()
	defer call.RUnlock()

	return call.transferFrom
}

func (call *CallImpl) TransferToAgentId() *int {
	call.RLock()
	defer call.RUnlock()

	return call.transferToAgentId
}

func (call *CallImpl) TransferFromAttemptId() *int64 {
	call.RLock()
	defer call.RUnlock()

	return call.transferFromAttemptId
}

func (call *CallImpl) TransferToAttemptId() *int64 {
	call.RLock()
	defer call.RUnlock()

	return call.transferToAttemptId
}

func (call *CallImpl) AcceptAt() int64 {
	return call.acceptAt
}

func (call *CallImpl) Answered() bool {
	call.RLock()
	a := call.acceptAt
	call.RUnlock()
	return a > 0
}

func (call *CallImpl) BridgeAt() int64 {
	return call.bridgeAt
}

func (call *CallImpl) HangupAt() int64 {
	call.RLock()
	defer call.RUnlock()
	return call.hangupAt
}

func (call *CallImpl) IsHuman() bool {
	return call.amdResult == AmdHuman || call.amdResult == AmdNotSure
}

func (call *CallImpl) DurationSeconds() int {
	if call.hangupAt > 0 {
		return int(call.hangupAt-call.ringingAt) / 1000
	} else {
		return int(model.GetMillis()-call.ringingAt) / 1000
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
		return int(call.acceptAt-call.ringingAt) / 1000
	} else {
		return 0
	}
}

func (call *CallImpl) WaitSeconds() int {
	if call.bridgeAt > 0 {
		return int(call.bridgeAt-call.ringingAt) / 1000
	} else {
		return int(model.GetMillis()-call.ringingAt) / 1000
	}
}

func (call *CallImpl) Err() *model.AppError {
	code := call.HangupCauseCode()
	if code != 0 && code != 200 {
		return model.NewAppError("Call", "call.app.error", nil, "error", http.StatusInternalServerError)
	}

	return nil
}

func (call *CallImpl) Hangup(cause string, reporting bool, vars map[string]string) *model.AppError {
	if call.GetState() < CALL_STATE_INVITE {
		wlog.Debug(fmt.Sprintf("[%s] call %s set cancel %s", call.NodeName(), call.Id(), cause))
		call.setCancel(cause)
		if call.GetState() == CALL_STATE_NEW {
			close(call.hangupCh)
		}
		return nil
	}

	if cause == "" {
		cause = model.CALL_HANGUP_NORMAL_CLEARING
	}

	wlog.Debug(fmt.Sprintf("[%s] call %s send hangup %s", call.NodeName(), call.Id(), cause))
	// todo set variables
	err := call.api.HangupCall(call.id, cause, reporting, vars)
	if err != nil && call.HangupCause() == "" {
		call.setHangup(&model.CallActionHangup{
			CallAction: model.CallAction{
				Id:        call.Id(),
				Timestamp: model.GetMillis(),
				Event:     model.CALL_HANGUP_APPLICATION,
			},
			Cause:   cause,
			SipCode: nil, // todo model.NewInt(500),
		})
	}
	return err
}

//func (call *CallImpl) ExecuteApplications(apps []*model.CallRequestApplication) *model.AppError {
//	return call.api.ExecuteApplications(call.id, apps)
//}

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

func (call *CallImpl) SetOtherChannelVar(vars map[string]string) *model.AppError {
	call.Lock()
	br := call.bridgedId
	call.Unlock()
	if br != nil {
		return call.api.SetCallVariables(*br, vars)
	}

	// TODO
	return nil
}

func (call *CallImpl) BroadcastPlaybackFile(domainId int64, file *model.RingtoneFile, leg string) *model.AppError {
	if file == nil {

		return nil
	}
	return call.api.BroadcastPlaybackFile(call.id, model.RingtoneUri(domainId, file.Id, file.Type), leg)
}

func (call *CallImpl) ParkPlaybackFile(domainId int64, file *model.RingtoneFile, leg string) *model.AppError {
	if file == nil {

		return nil
	}
	return call.api.ParkPlaybackFile(call.id, model.RingtoneUri(domainId, file.Id, file.Type), leg)
}

func (call *CallImpl) BroadcastTone(tone *string, leg string) *model.AppError {
	t := ""
	if tone == nil {
		t = "L=1;%(500,500,1000)"
	} else {
		t, _ = model.ToneList[*tone]
	}

	if t == "" || t == "none" {
		// skipp
		return nil
	}

	return call.api.BroadcastPlaybackFile(call.id, "tone_stream://"+t, leg)
}

func (call *CallImpl) BroadcastPlaybackSilenceBeforeFile(domainId int64, silence uint, file *model.RingtoneFile, leg string) *model.AppError {
	if file == nil {

		return nil
	}

	if silence == 0 {
		return call.api.BroadcastPlaybackFile(call.id, model.RingtoneUri(domainId, file.Id, file.Type), leg)
	}

	return call.api.BroadcastPlaybackFile(call.id, fmt.Sprintf("file_string://silence_stream://%d!%s", silence, model.RingtoneUri(domainId, file.Id, file.Type)), leg)
}

// FIXME
func (call *CallImpl) JoinQueue(ctx context.Context, id string, filePath string, vars map[string]string) *model.AppError {
	return call.api.JoinQueue(ctx, id, filePath, vars)
}

func (call *CallImpl) SerVariables(vars map[string]string) *model.AppError {
	return call.api.SetCallVariables(call.id, vars)
}

func (call *CallImpl) UpdateCid() *model.AppError {
	if call.info.To == nil {
		return nil
	}
	return call.api.UpdateCid(call.id, call.info.To.Number, call.info.To.Name)
}

func (call *CallImpl) ResetBridge() {
	call.Lock()
	call.bridgeAt = 0
	call.bridgedId = nil
	call.Unlock()
}

func (call *CallImpl) Stats() map[string]string {
	vars := map[string]string{
		"call_bill_sec": fmt.Sprintf("%d", call.BillSeconds()),
		"call_duration": fmt.Sprintf("%d", call.DurationSeconds()),
		"call_cause":    call.HangupCause(),
	}

	expVars := call.Variables()

	for k, v := range expVars {
		vars[k] = fmt.Sprintf("%v", v)
	}

	code := call.HangupCauseCode()
	if code > 0 {
		vars["call_sip_code"] = fmt.Sprintf("%d", call.HangupCauseCode())
	}

	if call.amdResult != "" {
		vars["amd_result"] = call.amdResult
	}

	var ans int64
	if call.acceptAt != 0 {
		ans = call.acceptAt
	} else if call.bridgeAt != 0 {
		ans = call.bridgeAt
	}

	if ans > 0 {
		h := call.hangupAt
		if h == 0 {
			h = model.GetMillis()
		}
		vars["call_voice_sec"] = fmt.Sprintf("%d", int((h-ans)/1000))
	}

	return vars
}
