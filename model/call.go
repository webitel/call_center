package model

const (
	CALL_STRATEGY_DEFAULT = iota
	CALL_STRATEGY_FAILOVER
	CALL_STRATEGY_MULTIPLE
)

const (
	CALL_DIRECTION_INBOUND  = "inbound"
	CALL_DIRECTION_OUTBOUND = "outbound"
	CALL_DIRECTION_DIALER   = "dialer"
)

const (
	CALL_EVENT_CREATE   = "CHANNEL_CREATE"
	CALL_EVENT_ANSWER   = "CHANNEL_ANSWER"
	CALL_EVENT_PARK     = "CHANNEL_PARK"
	CALL_EVENT_HANGUP   = "CHANNEL_HANGUP_COMPLETE"
	CALL_EVENT_BRIDGE   = "CHANNEL_BRIDGE"
	CALL_EVENT_UNBRIDGE = "CHANNEL_UNBRIDGE"
)

const (
	CALL_TIMEOUT_VARIABLE                = "call_timeout"
	CALL_HANGUP_CAUSE_VARIABLE           = "hangup_cause"
	CALL_PROGRESS_TIMEOUT_VARIABLE       = "progress_timeout"
	CALL_DOMAIN_VARIABLE                 = "domain_name"
	CALL_IGNORE_EARLY_MEDIA_VARIABLE     = "ignore_early_media"
	CALL_DIRECTION_VARIABLE              = "webitel_direction"
	CALL_RECORD_MIN_SEC_VARIABLE         = "RECORD_MIN_SEC"
	CALL_RECORD_STEREO_VARIABLE          = "RECORD_STEREO"
	CALL_RECORD_BRIDGE_REQ_VARIABLE      = "RECORD_BRIDGE_REQ"
	CALL_RECORD_FLLOW_TRANSFER_VARIABLE  = "recording_follow_transfer"
	CALL_RECORD_SESSION_TEMPLATE         = `http_cache://$${cdr_url}/sys/formLoadFile?domain=${domain_name}&id=${uuid}&type=mp3&email=none&name=recordSession&.mp3`
	CALL_RECORD_SESSION_APPLICATION_NAME = "record_session"

	CALL_SLEEP_APPLICATION    = "sleep"
	CALL_PLAYBACK_APPLICATION = "playback"
	CALL_TRANSFER_APPLICATION = "transfer"
	CALL_HANGUP_APPLICATION   = "hangup"
)

const (
	CALL_HANGUP_REJECTED  = "CALL_REJECTED"
	CALL_HANGUP_NO_ANSWER = "NO_ANSWER"
	CALL_HANGUP_USER_BUSY = "USER_BUSY"

	CALL_HANGUP_NORMAL_UNSPECIFIED = "NORMAL_UNSPECIFIED"
)

const (
	CALL_AMD_APPLICATION_NAME  = "amd"
	CALL_AMD_HUMAN_VARIABLE    = "amd_on_human"
	CALL_AMD_MACHINE_VARIABLE  = "amd_on_machine"
	CALL_AMD_NOT_SURE_VARIABLE = "amd_on_notsure"
)

type CallRequestApplication struct {
	AppName string
	Args    string
}

type CallRequest struct {
	Endpoints    []string
	Strategy     uint8
	Destination  string
	Variables    map[string]string
	Timeout      uint16
	CallerName   string
	CallerNumber string
	Dialplan     string
	Context      string
	Applications []*CallRequestApplication
}

type Call struct {
	Id           string
	State        string //
	CallerNumber string
	CalleeNumber string
}
