package client

import (
	"context"
	proto "github.com/webitel/call_center/grpc_api/cc"
)

type memberApi struct {
	cli *ccManager
}

func NewMemberApi(m *ccManager) MemberApi {
	return &memberApi{
		cli: m,
	}
}

func (api *memberApi) JoinCallToQueue(domainId int64, callId string, queueId int64, queueName string, priority int) (string, error) {
	cli, err := api.cli.getRandomClient()
	if err != nil {
		return "", err
	}
	res, err := cli.member.CallJoinToQueue(context.Background(), &proto.CallJoinToQueueRequest{
		CallId:    callId,
		QueueName: queueName,
		QueueId:   queueId,
		Priority:  int32(priority),
		DomainId:  domainId,
	})

	if err != nil {
		return "", err
	}

	return res.Status, nil
}
