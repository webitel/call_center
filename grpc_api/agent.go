package grpc_api

import (
	"context"
	"github.com/webitel/call_center/app"
	"github.com/webitel/call_center/model"
	"github.com/webitel/protos/cc"
)

type agent struct {
	app *app.App
}

func NewAgentApi(app *app.App) *agent {
	return &agent{app}
}

func (api *agent) Online(ctx context.Context, in *cc.OnlineRequest) (*cc.OnlineResponse, error) {
	info, err := api.app.SetAgentOnline(int(in.AgentId), in.GetOnDemand())
	if err != nil {
		return nil, err
	}

	return &cc.OnlineResponse{
		Timestamp: info.Timestamp,
		Channel: &cc.Channel{
			Channel:  info.Channel.Channel,
			State:    info.Channel.State,
			JoinedAt: info.Channel.JoinedAt,
		},
	}, nil
}

func (api *agent) Offline(ctx context.Context, in *cc.OfflineRequest) (*cc.OfflineResponse, error) {
	err := api.app.SetAgentLogout(int(in.AgentId))
	if err != nil {
		return nil, err
	}

	return &cc.OfflineResponse{}, nil
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

func (api *agent) WaitingChannel(ctx context.Context, in *cc.WaitingChannelRequest) (*cc.WaitingChannelResponse, error) {
	timestamp, err := api.app.WaitingAgentChannel(int(in.AgentId), in.Channel)
	if err != nil {
		return nil, err
	}

	return &cc.WaitingChannelResponse{
		Timestamp: timestamp,
	}, nil
}

func (api *agent) AcceptTask(_ context.Context, in *cc.AcceptTaskRequest) (*cc.AcceptTaskResponse, error) {
	//fixme find server id;
	err := api.app.AcceptAgentTask(in.Id)
	if err != nil {
		return nil, err
	}

	return &cc.AcceptTaskResponse{}, nil
}

func (api *agent) CloseTask(_ context.Context, in *cc.CloseTaskRequest) (*cc.CloseTaskResponse, error) {
	//fixme find server id;
	err := api.app.CloseAgentTask(in.Id)
	if err != nil {
		return nil, err
	}

	return &cc.CloseTaskResponse{}, nil
}
