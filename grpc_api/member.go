package grpc_api

import (
	"context"
	"fmt"
	"github.com/webitel/call_center/app"
	"github.com/webitel/call_center/grpc_api/cc"
	"github.com/webitel/call_center/model"
)

type member struct {
	app *app.App
}

func NewMemberApi(app *app.App) *member {
	return &member{app}
}

func (api *member) AttemptResult(ctx context.Context, in *cc.AttemptResultRequest) (*cc.AttemptResultResponse, error) {
	result := model.AttemptResult2{
		Success:     false,
		Status:      in.GetStatus(),
		Description: in.GetDescription(),
		Display:     in.GetDisplay(),
	}

	if in.ExpireAt > 0 {
		result.ExpireAt = model.NewInt64(in.GetExpireAt())
	}

	if in.MinOfferingAt > 0 {
		result.NextCall = model.NewInt64(in.MinOfferingAt)
	}

	err := api.app.Queue().Manager().ReportingAttempt(in.AttemptId, result)
	if err != nil {
		return nil, err
	}
	return &cc.AttemptResultResponse{
		Status: "success", //TODO
	}, nil
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

func (api *member) ChatJoinToQueue(ctx context.Context, in *cc.ChatJoinToQueueRequest) (*cc.ChatJoinToQueueResponse, error) {
	queue, err := api.app.Queue().Manager().DistributeChatToQueue(int(in.QueueId), in.ChannelId, in.Name, in.Number, int(in.Priority))
	if err != nil {
		return nil, err
	}
	return &cc.ChatJoinToQueueResponse{
		Status:      "joined", // TODO
		QueueName:   queue.Name(),
		WelcomeText: fmt.Sprintf("Welcome to queue \"%s\"", queue.Name()),
	}, nil
}

func (api *member) DirectAgentToMember(ctx context.Context, in *cc.DirectAgentToMemberRequest) (*cc.DirectAgentToMemberResponse, error) {
	res, err := api.app.Queue().Manager().DistributeDirectMember(in.GetMemberId(), int(in.GetCommunicationId()), int(in.GetAgentId()))
	if err != nil {
		return nil, err
	}

	return &cc.DirectAgentToMemberResponse{
		AttemptId: res.Id(),
	}, nil
}

func (api *member) EmailJoinToQueue(ctx context.Context, in *cc.EmailJoinToQueueRequest) (*cc.EmailJoinToQueueResponse, error) {
	return nil, nil
}
