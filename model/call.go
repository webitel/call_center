package model

type CallRequest struct {
	Endpoints    []string
	Destination  string
	Variables    map[string]string
	Timeout      int32
	CallerName   string
	CallerNumber string
	Dialplan     string
	Context      string
}

type Call struct {
	Id           string
	State        string //
	CallerNumber string
	CalleeNumber string
}
