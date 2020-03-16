package grpc_api

import (
	"github.com/webitel/call_center/app"
	"github.com/webitel/call_center/grpc_api/cc"
	"google.golang.org/grpc"
)

type API struct {
	app *app.App

	agent *agent
}

func Init(a *app.App, server *grpc.Server) {
	api := &API{
		app: a,
	}
	api.agent = NewAgentApi(a)

	cc.RegisterAgentServiceServer(server, api.agent)
}
