package grpc_api

import (
	"context"
	"github.com/webitel/call_center/app"
	"github.com/webitel/call_center/grpc_api/cc"
	"github.com/webitel/call_center/model"
)

type agent struct {
	app *app.App
}

func NewAgentApi(app *app.App) *agent {
	return &agent{app}
}

func (api *agent) Login(ctx context.Context, in *cc.LoginRequest) (*cc.LoginResponse, error) {
	err := api.app.SetAgentLogin(int(in.AgentId))
	if err != nil {
		return nil, err
	}

	return &cc.LoginResponse{}, nil
}

func (api *agent) Logout(ctx context.Context, in *cc.LogoutRequest) (*cc.LogoutResponse, error) {
	err := api.app.SetAgentLogout(int(in.AgentId))
	if err != nil {
		return nil, err
	}

	return &cc.LogoutResponse{}, nil
}

func (api *agent) Pause(ctx context.Context, in *cc.PauseRequest) (*cc.PauseResponse, error) {
	var payload *string
	var timeout *int
	if in.Payload != "" {
		payload = &in.Payload
	}

	if in.Timeout != 0 {
		timeout = model.NewInt(int(in.Timeout))
	}

	err := api.app.SetAgentPause(int(in.AgentId), payload, timeout)
	if err != nil {
		return nil, err
	}

	return &cc.PauseResponse{}, nil
}
