package external_commands

import (
	"github.com/webitel/call_center/external_commands/grpc"
	"github.com/webitel/call_center/model"
)

func NewCallConnection(name, url string) (model.CallCommands, *model.AppError) {
	return grpc.NewCallConnection(name, url)
}
