package external_commands

import (
	"github.com/webitel/call_center/external_commands/grpc"
	"github.com/webitel/call_center/model"
)

func NewCallConnection(name, url string) (model.CallCommands, *model.AppError) {
	return grpc.NewCallConnection(name, url)
}

func NewAuthServiceConnection(name, url string) (model.AuthClient, *model.AppError) {
	return grpc.NewAuthServiceConnection(name, url)
}
