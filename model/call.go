package model

const (
	CALL_STRATEGY_DEFAULT = iota
	CALL_STRATEGY_FAILOVER
	CALL_STRATEGY_MULTIPLE
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
