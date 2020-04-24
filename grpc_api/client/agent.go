package client

import (
	"context"
	"github.com/webitel/call_center/grpc_api/cc"
)

type agentApi struct {
	cli *ccManager
}

func NewAgentApi(m *ccManager) AgentApi {
	return &agentApi{
		cli: m,
	}
}

func (api *agentApi) Online(domainId, agentId int64) error {
	cli, err := api.cli.getRandomClient()
	if err != nil {
		return err
	}

	_, err = cli.agent.Online(context.TODO(), &cc.OnlineRequest{
		AgentId:  agentId,
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
