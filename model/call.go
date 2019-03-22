package model

const (
	CALL_STRATEGY_DEFAULT = iota
	CALL_STRATEGY_FAILOVER
	CALL_STRATEGY_MULTIPLE
)

const (
	CALL_TIMEOUT_VARIABLE_NAME            = "call_timeout"
	CALL_DOMAIN_VARIABLE_NAME             = "domain_name"
	CALL_IGNORE_EARLY_MEDIA_VARIABLE_NAME = "ignore_early_media"
)

type CallRequestExtension struct {
	AppName string
	Args    string
}

type CallRequest struct {
	Endpoints    []string
	Strategy     int8
	Destination  string
	Variables    map[string]string
	Timeout      int32
	CallerName   string
	CallerNumber string
	Dialplan     string
	Context      string
	Extensions   []*CallRequestExtension
}

type Call struct {
	Id           string
	State        string //
	CallerNumber string
	CalleeNumber string
}
