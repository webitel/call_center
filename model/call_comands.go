package model

type CallCommands interface {
	NewCall(settings *CallRequest) (string, string, *AppError)
	HangupCall(id, cause string) *AppError
	SetCallVariables(id string, variables map[string]string) *AppError
	Close()
}
