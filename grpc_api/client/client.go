package client

import (
	"fmt"
	"github.com/webitel/call_center/grpc_api/cc"
	"github.com/webitel/call_center/model"
	"github.com/webitel/engine/discovery"
	"github.com/webitel/wlog"
	"sync"
)

const (
	WatcherInterval = 5 * 1000
)

type CCClient interface {
	Name() string
	Close() error
	Ready() bool
}

type CCManager interface {
	Start() error
	Stop()
	Agent() (cc.AgentServiceClient, error)
}

type ccManager struct {
	serviceDiscovery discovery.ServiceDiscovery
	poolConnections  discovery.Pool

	watcher   *discovery.Watcher
	startOnce sync.Once
	stop      chan struct{}
	stopped   chan struct{}
}

func NewCCManager(serviceDiscovery discovery.ServiceDiscovery) CCManager {
	return &ccManager{
		stop:             make(chan struct{}),
		stopped:          make(chan struct{}),
		poolConnections:  discovery.NewPoolConnections(),
		serviceDiscovery: serviceDiscovery,
	}
}

func (cc *ccManager) Agent() (cc.AgentServiceClient, error) {
	con, err := cc.poolConnections.Get(discovery.StrategyRoundRobin)
	if err != nil {
		return nil, err
	}

	return con.(*ccConnection).Agent, nil
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
