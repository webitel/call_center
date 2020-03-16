package grpc_api

import (
	"context"
	"errors"
	"fmt"
	"github.com/webitel/call_center/app"
	"github.com/webitel/call_center/grpc_api/cc"
)

type agent struct {
	app *app.App
}

func NewAgentApi(app *app.App) *agent {
	return &agent{app}
}

func (api *agent) SetStatus(ctx context.Context, in *cc.SetStatusRequest) (*cc.SetStatusResponse, error) {
	fmt.Println("RECIVE")
	return nil, errors.New("TODO")
}
