package client

import (
	cc "buf.build/gen/go/webitel/cc/protocolbuffers/go"
	"context"
)

type agentApi struct {
	cli *ccManager
}

func NewAgentApi(m *ccManager) AgentApi {
	return &agentApi{
		cli: m,
	}
}

func (api *agentApi) Online(domainId, agentId int64, onDemand bool) error {
	cli, err := api.cli.getRandomClient()
	if err != nil {
		return err
	}

	_, err = cli.agent.Online(context.TODO(), &cc.OnlineRequest{
		AgentId:  agentId,
		OnDemand: onDemand,
		DomainId: domainId,
	})
	return err
}

func (api *agentApi) Offline(domainId, agentId int64) error {
	cli, err := api.cli.getRandomClient()
	if err != nil {
		return err
	}

	_, err = cli.agent.Offline(context.TODO(), &cc.OfflineRequest{
		AgentId:  agentId,
		DomainId: domainId,
	})
	return err
}

func (api *agentApi) Pause(domainId, agentId int64, payload string, timeout int) error {
	cli, err := api.cli.getRandomClient()
	if err != nil {
		return err
	}

	_, err = cli.agent.Pause(context.TODO(), &cc.PauseRequest{
		AgentId:  agentId,
		Payload:  payload,
		Timeout:  int32(timeout),
		DomainId: domainId,
	})
	return err
}

func (api *agentApi) WaitingChannel(agentId int, channel string) (int64, error) {
	cli, err := api.cli.getRandomClient()
	if err != nil {
		return 0, err
	}

	if res, err := cli.agent.WaitingChannel(context.TODO(), &cc.WaitingChannelRequest{
		AgentId: int32(agentId),
		Channel: channel,
	}); err != nil {
		return 0, err
	} else {
		return res.Timestamp, nil
	}

}

func (api *agentApi) AcceptTask(appId string, domainId, attemptId int64) error {
	cli, err := api.cli.getClient(appId)
	if err != nil {
		return err
	}

	_, err = cli.agent.AcceptTask(context.Background(), &cc.AcceptTaskRequest{
		Id:       attemptId,
		AppId:    appId,
		DomainId: domainId,
	})

	return err
}

func (api *agentApi) CloseTask(appId string, domainId, attemptId int64) error {
	cli, err := api.cli.getClient(appId)
	if err != nil {
		return err
	}

	_, err = cli.agent.CloseTask(context.Background(), &cc.CloseTaskRequest{
		Id:       attemptId,
		AppId:    appId,
		DomainId: domainId,
	})

	return err
}

func (api *agentApi) RunTrigger(ctx context.Context, domainId int64, userId int64, triggerId int32, vars map[string]string) (string, error) {
	cli, err := api.cli.getRandomClient()
	if err != nil {
		return "", err
	}

	var res *cc.RunTriggerResponse
	res, err = cli.Agent().RunTrigger(ctx, &cc.RunTriggerRequest{
		DomainId:  domainId,
		TriggerId: triggerId,
		UserId:    userId,
		Variables: vars,
	})

	if err != nil {
		return "", err
	}

	return res.JobId, nil
}
