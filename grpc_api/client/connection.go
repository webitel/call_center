package client

import (
	"github.com/webitel/call_center/grpc_api/cc"
	"google.golang.org/grpc"
	"google.golang.org/grpc/connectivity"
	"time"
)

type ccConnection struct {
	name   string
	host   string
	client *grpc.ClientConn
	Agent  cc.AgentServiceClient
}

func NewCCConnection(name, url string) (CCClient, error) {
	var err error
	connection := &ccConnection{
		name: name,
		host: url,
	}

	connection.client, err = grpc.Dial(url, grpc.WithInsecure(), grpc.WithBlock(), grpc.WithTimeout(2*time.Second))

	if err != nil {
		return nil, err
	}

	connection.Agent = cc.NewAgentServiceClient(connection.client)

	return connection, nil
}

func (cc *ccConnection) Ready() bool {
	switch cc.client.GetState() {
	case connectivity.Idle, connectivity.Ready:
		return true
	}
	return false
}

func (cc *ccConnection) Name() string {
	return cc.name
}

func (cc *ccConnection) Close() error {
	err := cc.client.Close()
	if err != nil {
		return ErrInternal
	}
	return nil
}
