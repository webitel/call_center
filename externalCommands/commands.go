package externalCommands

import (
	"github.com/webitel/call_center/externalCommands/grpc"
	"github.com/webitel/call_center/model"
)

func NewCallCommands(settings model.ExternalCommandsSettings) model.CallCommands {
	return grpc.NewCallCommands(settings)
}
