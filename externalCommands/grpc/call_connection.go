package grpc

import (
	"context"
	"github.com/webitel/call_center/externalCommands/grpc/fs"
	"github.com/webitel/call_center/model"
	"google.golang.org/grpc"
	"net/http"
	"strings"
)

type CallConnection struct {
	name   string
	client *grpc.ClientConn
	api    fs.ApiClient
}

func newConnection(host string, opts []grpc.DialOption) (*CallConnection, error) {
	client, err := grpc.Dial(host, opts...)
	if err != nil {
		return nil, err
	}

	return &CallConnection{
		name:   `fs-` + host,
		client: client,
		api:    fs.NewApiClient(client),
	}, nil

}

func (c *CallConnection) GetServerVersion() (string, *model.AppError) {
	res, err := c.api.Execute(context.Background(), &fs.ExecuteRequest{
		Command: "version",
	})

	if err != nil {
		return "", model.NewAppError("ServerVersion", "external.get_server_version.app_error", nil, err.Error(),
			http.StatusInternalServerError)
	}

	return strings.TrimSpace(res.Data), nil
}

func (c *CallConnection) NewCall(settings *model.CallRequest) (string, string, *model.AppError) {
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

	if len(settings.Applications) > 0 {
		request.Extensions = []*fs.OriginateRequest_Extension{}

		for _, v := range settings.Applications {
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

func (c *CallConnection) HangupCall(id, cause string) *model.AppError {
	_, err := c.api.Hangup(context.Background(), &fs.HangupRequest{
		Uuid:  id,
		Cause: cause,
	})

	if err != nil {
		return model.NewAppError("HangupCall", "external.hangup_call.app_error", nil, err.Error(),
			http.StatusInternalServerError)
	}
	return nil
}

func (c *CallConnection) SetCallVariables(id string, variables map[string]string) *model.AppError {

	res, err := c.api.SetVariables(context.Background(), &fs.SetVariablesReqeust{
		Uuid:      id,
		Variables: variables,
	})

	if err != nil {
		return model.NewAppError("SetCallVariables", "external.set_call_variables.app_error", nil, err.Error(),
			http.StatusInternalServerError)
	}

	if res.Error != nil {
		return model.NewAppError("SetCallVariables", "external.set_call_variables.app_error", nil, res.Error.String(),
			http.StatusInternalServerError)
	}

	return nil
}

func (c *CallConnection) BridgeCall(legAId, legBId, legBReserveId string) (string, *model.AppError) {
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

func (c *CallConnection) close() {
	c.client.Close()
}
