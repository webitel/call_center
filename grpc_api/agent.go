package grpc_api

import (
	"context"

	"github.com/webitel/call_center/app"
	"github.com/webitel/call_center/gen/cc"
	"github.com/webitel/call_center/model"
	"github.com/webitel/engine/pkg/wbt/gen/engine"
)

type agent struct {
	cc.UnsafeAgentServiceServer

	app *app.App
}

func NewAgentApi(a *app.App) *agent { return &agent{app: a} }

func AgentChannelToCC(channel model.AgentChannel) *cc.Channel {
	return &cc.Channel{
		Channel:  channel.Channel,
		State:    channel.State,
		JoinedAt: channel.JoinedAt,
	}
}

func AgentChannelsToCC(channels []model.AgentChannel) []*cc.Channel {
	res := make([]*cc.Channel, 0, len(channels))

	for _, channel := range channels {
		res = append(res, AgentChannelToCC(channel))
	}

	return res
}

func (api *agent) Online(ctx context.Context, in *cc.OnlineRequest) (*cc.OnlineResponse, error) {
	info, err := api.app.AgentGoOnline(
		ctx,
		&model.AgentOnlineRequest{
			AgentID:  in.GetAgentId(),
			OnDemand: in.GetOnDemand(),
			DomainID: in.GetDomainId(),
			Status: &model.Lookup{
				Id:   int(in.GetOnlineSkill().GetId()),
				Name: in.GetOnlineSkill().GetName(),
			},
		},
	)

	if err != nil {
		return nil, err
	}

	var preset *engine.Lookup
	if !info.IsStatusPresetEmpty() {
		preset = &engine.Lookup{Id: int64(info.StatusPreset.Id), Name: info.StatusPreset.Name}
	}

	return &cc.OnlineResponse{
		Timestamp:   info.Timestamp,
		Channel:     AgentChannelsToCC(info.Channel),
		OnlineSkill: preset,
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
	var payload, statusComment *string
	var timeout *int
	if in.Payload != "" {
		payload = &in.Payload
	}

	if in.StatusComment != "" {
		statusComment = &in.StatusComment
	}

	if in.Timeout != 0 {
		timeout = model.NewInt(int(in.Timeout))
	}

	err := api.app.SetAgentPause(int(in.AgentId), payload, statusComment, timeout)
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

func (api *agent) RunTrigger(ctx context.Context, in *cc.RunTriggerRequest) (*cc.RunTriggerResponse, error) {
	jobId, err := api.app.RunTeamTrigger(ctx, in.DomainId, in.UserId, in.TriggerId, in.Variables)
	if err != nil {
		return nil, err
	}

	return &cc.RunTriggerResponse{
		JobId: jobId,
	}, nil
}
