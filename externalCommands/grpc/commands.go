package grpc

import (
	"context"
	"fmt"
	"github.com/webitel/call_center/externalCommands"
	"github.com/webitel/call_center/externalCommands/grpc/fs"
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
	"google.golang.org/grpc"
	"net/http"
	"os"
	"time"
)

type CommandsImpl struct {
	client *grpc.ClientConn
	api    fs.ApiClient
}

func NewCommands(settings model.ExternalCommandsSettings) externalCommands.Commands {
	var opts []grpc.DialOption

	if settings.Url == nil {
		mlog.Critical(fmt.Sprintf("Failed openg grpc connection %v", *settings.Url))
		time.Sleep(time.Second)
		os.Exit(1)
	}

	opts = append(opts, grpc.WithInsecure(), grpc.WithBlock(), grpc.WithTimeout(10*time.Second))
	client, err := grpc.Dial(*settings.Url, opts...)

	if err != nil {
		mlog.Critical(fmt.Sprintf("Failed openg grpc connection %v", *settings.Url))
		time.Sleep(time.Second)
		os.Exit(1)
	}

	api := fs.NewApiClient(client)

	r := &CommandsImpl{
		client: client,
		api:    api,
	}

	mlog.Debug(fmt.Sprintf("Success open grpc connection %v", *settings.Url))
	return r
}

func (c *CommandsImpl) NewCall(settings *model.CallRequest) (string, *model.AppError) {
	response, err := c.api.Originate(context.Background(), &fs.OriginateRequest{
		Endpoints:    settings.Endpoints,
		Destination:  settings.Destination,
		CallerNumber: settings.CallerNumber,
		CallerName:   settings.CallerName,
		Timeout:      settings.Timeout,
		Context:      settings.Context,
		Dialplan:     settings.Dialplan,
		Variables:    settings.Variables,
	})

	if err != nil {
		return "", model.NewAppError("NewCall", "external.NewCall.app_error", nil, err.Error(),
			http.StatusInternalServerError)
	}

	if response.Error != nil {
		return "", model.NewAppError("NewCall", "external.NewCall.app_error", nil, response.Error.String(),
			http.StatusInternalServerError)
	}

	return response.Uuid, nil
}

func (c *CommandsImpl) HangupCall(id, cause string) *model.AppError {
	_, err := c.api.Hangup(context.Background(), &fs.HangupRequest{
		Uuid: id,
	})

	if err != nil {
		return model.NewAppError("HangupCall", "external.HangupCall.app_error", nil, err.Error(),
			http.StatusInternalServerError)
	}
	return nil
}

func (c *CommandsImpl) Close() {
	mlog.Debug(fmt.Sprintf("Receive close grpc connection"))
	c.client.Close()
}
