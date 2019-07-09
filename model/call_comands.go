package model

type CallCommands interface {
	NewCall(settings *CallRequest) (string, string, *AppError)
	HangupCall(id, cause string) *AppError
	Hold(id string) *AppError
	SetCallVariables(id string, variables map[string]string) *AppError
}

type Commands interface {
	GetCallConnection() CallCommands
	GetCallConnectionByName(name string) (*AppError, CallCommands)
	Close()
}
