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
	CALL_TIMEOUT_VARIABLE_NAME            = "call_timeout"
	CALL_PROGRESS_TIMEOUT_VARIABLE_NAME   = "progress_timeout"
	CALL_DOMAIN_VARIABLE_NAME             = "domain_name"
	CALL_IGNORE_EARLY_MEDIA_VARIABLE_NAME = "ignore_early_media"
	CALL_DIRECTION_VARIABLE_NAME          = "webitel_direction"
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
