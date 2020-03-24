package client

import (
	"context"
	"fmt"
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

func (api *memberApi) JoinCallToQueue(domainId int64, callId string, queueId int64, queueName string, priority int) error {
	cli, err := api.cli.getRandomClient()
	if err != nil {
		return err
	}
	res, err := cli.member.CallJoinToQueue(context.Background(), &proto.CallJoinToQueueRequest{
		CallId:    callId,
		QueueName: queueName,
		QueueId:   queueId,
		Priority:  int32(priority),
		DomainId:  domainId,
	})

	fmt.Println(res)
	return err
}
