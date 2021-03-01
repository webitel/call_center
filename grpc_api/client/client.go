package client

import (
	"context"
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/engine/discovery"
	"github.com/webitel/protos/cc"
	"github.com/webitel/wlog"
	"sync"
)

const (
	WatcherInterval = 5 * 1000
)

type AgentApi interface {
	Online(domainId, agentId int64, onDemand bool) error
	Offline(domainId, agentId int64) error
	Pause(domainId, agentId int64, payload string, timeout int) error

	WaitingChannel(agentId int, channel string) (int64, error)

	AcceptTask(appId string, domainId, attemptId int64) error
	CloseTask(appId string, domainId, attemptId int64) error
}

type MemberApi interface {
	AttemptResult(attemptId int64, status, description string, nextOffering *int64, expireAt *int64, vars map[string]string,
		stickyDisplay bool, agentId int32) error
	RenewalResult(domainId, attemptId int64, renewal uint32) error

	JoinCallToQueue(ctx context.Context, in *cc.CallJoinToQueueRequest) (cc.MemberService_CallJoinToQueueClient, error)
	JoinChatToQueue(ctx context.Context, in *cc.ChatJoinToQueueRequest) (cc.MemberService_ChatJoinToQueueClient, error)
	DirectAgentToMember(domainId int64, memberId int64, communicationId int, agentId int64) (int64, error)
}

type CCManager interface {
	Start() error
	Stop()

	Agent() AgentApi
	Member() MemberApi
}

type ccManager struct {
	serviceDiscovery discovery.ServiceDiscovery
	poolConnections  discovery.Pool

	watcher   *discovery.Watcher
	startOnce sync.Once
	stop      chan struct{}
	stopped   chan struct{}

	agent  AgentApi
	member MemberApi
}

func NewCCManager(serviceDiscovery discovery.ServiceDiscovery) CCManager {
	cli := &ccManager{
		stop:             make(chan struct{}),
		stopped:          make(chan struct{}),
		poolConnections:  discovery.NewPoolConnections(),
		serviceDiscovery: serviceDiscovery,
	}

	cli.agent = NewAgentApi(cli)
	cli.member = NewMemberApi(cli)

	return cli
}

func (cc *ccManager) Agent() AgentApi {
	return cc.agent
}

func (cc *ccManager) Member() MemberApi {
	return cc.member
}

func (cc *ccManager) Start() error {
	wlog.Debug("starting cc service")

	if services, err := cc.serviceDiscovery.GetByName(model.ServiceName); err != nil {
		return err
	} else {
		for _, v := range services {
			cc.registerConnection(v)
		}
	}

	cc.startOnce.Do(func() {
		cc.watcher = discovery.MakeWatcher("cc manager", WatcherInterval, cc.wakeUp)
		go cc.watcher.Start()
		go func() {
			defer func() {
				wlog.Debug("stopped cc manager")
				close(cc.stopped)
			}()

			for {
				select {
				case <-cc.stop:
					wlog.Debug("cc manager received stop signal")
					return
				}
			}
		}()
	})
	return nil
}

func (cc *ccManager) Stop() {
	if cc.watcher != nil {
		cc.watcher.Stop()
	}

	if cc.poolConnections != nil {
		cc.poolConnections.CloseAllConnections()
	}

	close(cc.stop)
	<-cc.stopped
}

func (cc *ccManager) registerConnection(v *discovery.ServiceConnection) {
	addr := fmt.Sprintf("%s:%d", v.Host, v.Port)
	client, err := NewCCConnection(v.Id, addr)
	if err != nil {
		wlog.Error(fmt.Sprintf("connection %s [%s] error: %s", v.Id, addr, err.Error()))
		return
	}
	cc.poolConnections.Append(client)
	wlog.Debug(fmt.Sprintf("register connection %s [%s]", client.Name(), addr))
}

func (cc *ccManager) wakeUp() {
	list, err := cc.serviceDiscovery.GetByName(model.ServiceName)
	if err != nil {
		wlog.Error(err.Error())
		return
	}

	for _, v := range list {
		if _, err := cc.poolConnections.GetById(v.Id); err == discovery.ErrNotFoundConnection {
			cc.registerConnection(v)
		}
	}
	cc.poolConnections.RecheckConnections()
}

func (cc *ccManager) getRandomClient() (*ccConnection, error) {
	cli, err := cc.poolConnections.Get(discovery.StrategyRoundRobin)
	if err != nil {
		return nil, err
	}

	return cli.(*ccConnection), nil
}

func (cc *ccManager) getClient(appId string) (*ccConnection, error) {
	cli, err := cc.poolConnections.GetById(appId)
	if err != nil {
		return nil, err
	}

	return cli.(*ccConnection), nil
}
