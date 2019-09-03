package auth_manager

import (
	"fmt"
	"github.com/webitel/call_center/cluster"
	"github.com/webitel/call_center/external_commands"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"sync"
)

const (
	WATCHER_INTERVAL  = 5 * 1000
	AUTH_SERVICE_NAME = "go.webitel.dsa1"
)

type AuthManager interface {
	Start() *model.AppError
	Stop()
	GetSession(token string) (*model.Session, *model.AppError)
}

type authManager struct {
	session          utils.ObjectCache
	serviceDiscovery cluster.ServiceDiscovery
	poolConnections  cluster.Pool

	watcher   *utils.Watcher
	startOnce sync.Once
	stop      chan struct{}
	stopped   chan struct{}
}

func NewAuthManager(serviceDiscovery cluster.ServiceDiscovery) AuthManager {
	return &authManager{
		stop:             make(chan struct{}),
		stopped:          make(chan struct{}),
		poolConnections:  cluster.NewPoolConnections(),
		session:          utils.NewLruWithParams(model.SESSION_CACHE_SIZE, "auth manager", model.SESSION_CACHE_TIME, ""), //TODO session from config ?
		serviceDiscovery: serviceDiscovery,
	}
}

func (am *authManager) Start() *model.AppError {
	wlog.Debug("starting auth service")

	if services, err := am.serviceDiscovery.GetByName(AUTH_SERVICE_NAME); err != nil {
		return err
	} else {
		for _, v := range services {
			am.registerConnection(v)
		}
	}

	am.startOnce.Do(func() {
		am.watcher = utils.MakeWatcher("auth manager", WATCHER_INTERVAL, am.wakeUp)
		go am.watcher.Start()
		go func() {
			defer func() {
				wlog.Debug("stopper auth manager")
				close(am.stopped)
			}()

			for {
				select {
				case <-am.stop:
					wlog.Debug("auth manager received stop signal")
					return
				}
			}
		}()
	})
	return nil
}

func (am *authManager) Stop() {
	if am.watcher != nil {
		am.watcher.Stop()
	}

	if am.poolConnections != nil {
		am.poolConnections.CloseAllConnections()
	}

	close(am.stop)
	<-am.stopped
}

func (am *authManager) getAuthClient() (model.AuthClient, *model.AppError) {
	conn, err := am.poolConnections.Get(cluster.StrategyRoundRobin)
	if err != nil {
		return nil, err
	}
	return conn.(model.AuthClient), nil
}

func (am *authManager) registerConnection(v *model.ServiceConnection) {
	client, err := external_commands.NewAuthServiceConnection(v.Id, fmt.Sprintf("%s:%d", v.Host, v.Port))
	if err != nil {
		wlog.Error(fmt.Sprintf("connection %s error: %s", v.Id, err.Error()))
		return
	}
	am.poolConnections.Append(client)
	wlog.Debug(fmt.Sprintf("register connection %s", client.Name()))
}

func (am *authManager) wakeUp() {
	list, err := am.serviceDiscovery.GetByName(AUTH_SERVICE_NAME)
	if err != nil {
		wlog.Error(err.Error())
		return
	}

	for _, v := range list {
		if _, err := am.poolConnections.GetById(v.Id); err == cluster.ErrNotFoundConnection {
			am.registerConnection(v)
		}
	}
	am.poolConnections.RecheckConnections()
}
