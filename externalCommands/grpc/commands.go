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
	"strings"
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

	if version, err := r.GetServerVersion(); err == nil {
		mlog.Info(version)
	}

	mlog.Debug(fmt.Sprintf("Success open grpc connection %v", *settings.Url))
	return r
}

func (c *CommandsImpl) NewCall(settings *model.CallRequest) (string, string, *model.AppError) {
	request := &fs.OriginateRequest{
		Endpoints:    settings.Endpoints,
		Destination:  settings.Destination,
		CallerNumber: settings.CallerNumber,
		CallerName:   settings.CallerName,
		Timeout:      int32(settings.Timeout),
		Context:      settings.Context,
		Dialplan:     settings.Dialplan,
		Variables:    settings.Variables,
	}

	if len(settings.Extensions) > 0 {
		request.Extensions = []*fs.OriginateRequest_Extension{}

		for _, v := range settings.Extensions {
			request.Extensions = append(request.Extensions, &fs.OriginateRequest_Extension{
				AppName: v.AppName,
				Args:    v.Args,
			})
		}
	}

	switch settings.Strategy {
	case model.CALL_STRATEGY_FAILOVER:
		request.Strategy = fs.OriginateRequest_FAILOVER
		break
	case model.CALL_STRATEGY_MULTIPLE:
		request.Strategy = fs.OriginateRequest_MULTIPLE
		break
	}

	response, err := c.api.Originate(context.Background(), request)

	if err != nil {
		return "", "", model.NewAppError("NewCall", "external.new_call.app_error", nil, err.Error(),
			http.StatusInternalServerError)
	}

	if response.Error != nil {
		return "", response.Error.Message, model.NewAppError("NewCall", "external.new_call.app_error", nil, response.Error.String(),
			http.StatusInternalServerError)
	}

	return response.Uuid, "", nil
}

func (c *CommandsImpl) HangupCall(id, cause string) *model.AppError {
	_, err := c.api.Hangup(context.Background(), &fs.HangupRequest{
		Uuid: id,
	})

	if err != nil {
		return model.NewAppError("HangupCall", "external.hangup_call.app_error", nil, err.Error(),
			http.StatusInternalServerError)
	}
	return nil
}

func (c *CommandsImpl) BridgeCall(legAId, legBId, legBReserveId string) (string, *model.AppError) {
	response, err := c.api.Bridge(context.Background(), &fs.BridgeRequest{
		LegAId:        legAId,
		LegBId:        legBId,
		LegBReserveId: legBReserveId,
	})
	if err != nil {
		return "", model.NewAppError("BridgeCall", "external.bridge_call.app_error", nil, err.Error(),
			http.StatusInternalServerError)
	}

	if response.Error != nil {
		return "", model.NewAppError("BridgeCall", "external.bridge_call.app_error", nil, response.Error.String(),
			http.StatusInternalServerError)
	}

	return response.Uuid, nil
}

func (c *CommandsImpl) GetServerVersion() (string, *model.AppError) {
	res, err := c.api.Execute(context.Background(), &fs.ExecuteRequest{
		Command: "version",
	})

	if err != nil {
		return "", model.NewAppError("ServerVersion", "external.get_server_version.app_error", nil, err.Error(),
			http.StatusInternalServerError)
	}

	return strings.TrimSpace(res.Data), nil
}

func (c *CommandsImpl) Close() {
	mlog.Debug(fmt.Sprintf("Receive close grpc connection"))
	c.client.Close()
}

func (c *CommandsImpl) test() {
	c.NewCall(&model.CallRequest{
		Endpoints: []string{"user/1003@10.10.10.25"},
		Extensions: []*model.CallRequestExtension{
			{
				AppName: "sleep",
				Args:    "5000",
			},
			{
				AppName: "hangup",
			},
		},
	})
}
