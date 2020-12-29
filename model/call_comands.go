package model

import "context"

type CallCommandsEndpoint struct {
	Name string `json:"name" db:"name"`
	Host string `json:"host" db:"host"`
}

type CallCommands interface {
	Name() string
	Ready() bool

	GetServerVersion() (string, *AppError)
	SetConnectionSps(sps int) (int, *AppError)
	GetRemoteSps() (int, *AppError)
	GetParameter(name string) (string, *AppError)
	GetSocketUri() (string, *AppError)

	NewCall(settings *CallRequest) (string, string, *AppError)
	NewCallContext(ctx context.Context, settings *CallRequest) (string, string, *AppError)

	HangupCall(id, cause string, reporting bool) *AppError
	//ExecuteApplications(id string, apps []*CallRequestApplication) *AppError
	Hold(id string) *AppError
	SetCallVariables(id string, variables map[string]string) *AppError
	BridgeCall(legAId, legBId, legBReserveId string) (string, *AppError)
	DTMF(id string, ch rune) *AppError
	JoinQueue(ctx context.Context, id string, filePath string, vars map[string]string) *AppError
	BroadcastPlaybackFile(id, path, leg string) *AppError
	StopPlayback(id string) *AppError

	Close() error
}
