package grpc_api

import (
	gogrpc "buf.build/gen/go/webitel/cc/grpc/go/_gogrpc"
	"github.com/webitel/call_center/app"
	"google.golang.org/grpc"
)

type API struct {
	app *app.App

	agent  *agent
	member *member
}

func Init(a *app.App, server *grpc.Server) {
	api := &API{
		app: a,
	}
	api.agent = NewAgentApi(a)
	api.member = NewMemberApi(a)

	gogrpc.RegisterAgentServiceServer(server, api.agent)
	gogrpc.RegisterMemberServiceServer(server, api.member)
}
