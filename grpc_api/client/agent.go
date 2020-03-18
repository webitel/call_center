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

func (api *agentApi) Login(domainId, agentId int64) error {
	cli, err := api.cli.getRandomClient()
	if err != nil {
		return err
	}

	_, err = cli.agent.Login(context.TODO(), &cc.LoginRequest{
		AgentId:  agentId,
		DomainId: domainId,
	})
	return err
}

func (api *agentApi) Logout(domainId, agentId int64) error {
	cli, err := api.cli.getRandomClient()
	if err != nil {
		return err
	}

	_, err = cli.agent.Logout(context.TODO(), &cc.LogoutRequest{
		AgentId:  agentId,
		DomainId: domainId,
	})
	return err
}

func (api *agentApi) Pause(domainId, agentId int64, payload []byte, timeout int) error {
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
