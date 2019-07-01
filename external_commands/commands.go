package external_commands

import (
	"github.com/webitel/call_center/external_commands/grpc"
	"github.com/webitel/call_center/model"
)

func NewCallCommands(settings model.ExternalCommandsSettings) model.Commands {
	return grpc.NewCallCommands(settings)
}
