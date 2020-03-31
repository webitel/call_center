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
	attempt, err := api.app.Queue().Manager().DistributeCall(int(in.QueueId), in.CallId)
	if err != nil {
		return nil, err
	}
	return &cc.CallJoinToQueueResponse{
		Status: attempt.Result(),
	}, nil
}

func (api *member) DirectAgentToMember(ctx context.Context, in *cc.DirectAgentToMemberRequest) (*cc.DirectAgentToMemberResponse, error) {
	res, err := api.app.Queue().Manager().DistributeDirectMember(in.GetMemberId(), int(in.GetAgentId()))
	if err != nil {
		return nil, err
	}

	return &cc.DirectAgentToMemberResponse{
		AttemptId: res.Id(),
	}, nil
}
