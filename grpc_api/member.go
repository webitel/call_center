package grpc_api

import (
	"context"
	"github.com/webitel/call_center/app"
	"github.com/webitel/call_center/grpc_api/cc"
)

type member struct {
	app *app.App
}

func NewMemberApi(app *app.App) *member {
	return &member{app}
}

func (api *member) AttemptResult(ctx context.Context, in *cc.AttemptResultRequest) (*cc.AttemptResultResponse, error) {
	return nil, nil
}

func (api *member) CallJoinToQueue(ctx context.Context, in *cc.CallJoinToQueueRequest) (*cc.CallJoinToQueueResponse, error) {
	api.app.Queue().Manager().DistributeCall(int(in.QueueId), in.CallId)
	return nil, nil
}
