package cluster

import (
	"fmt"
	"github.com/hashicorp/consul/api"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
	"net/http"
	"time"
)

type consul struct {
	id              string
	cli             *api.Client
	kv              *api.KV
	agent           *api.Agent
	stop            chan struct{}
	check           func() (bool, *model.AppError)
	checkId         string
	registerService bool
}

func NewConsul(id string, check func() (bool, *model.AppError)) (*consul, *model.AppError) {
	conf := api.DefaultConfig()
	conf.Address = "192.168.177.199:8500"

	cli, err := api.NewClient(conf)

	if err != nil {
		return nil, model.NewAppError("Cluster.NewConsul", "cluster.consul.create.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}

	c := &consul{
		id:              id,
		registerService: true,
		cli:             cli,
		agent:           cli.Agent(),
		stop:            make(chan struct{}),
		check:           check,
		kv:              cli.KV(),
	}

	return c, nil
}

func (c *consul) GetByName(serviceName string) ([]*model.ServiceConnection, *model.AppError) {
	list, err := c.agent.ServicesWithFilter(fmt.Sprintf("Service == %s", serviceName))
	if err != nil {
		return nil, model.NewAppError("Cluster.GetServiceByName", "cluster.get_service_by_name.app_error", nil,
			fmt.Sprintf("Service=%v, %s", serviceName, err.Error()), http.StatusInternalServerError)
	}

	result := make([]*model.ServiceConnection, 0, len(list))
	for _, v := range list {
		result = append(result, &model.ServiceConnection{
			Id:      v.ID,
			Service: v.Service,
			Host:    v.Address,
			Port:    v.Port,
		})
	}

	return result, nil
}

func (c *consul) RegisterService() *model.AppError {
	if !c.registerService {
		return nil
	}

	var err error

	as := &api.AgentServiceRegistration{
		Name: model.APP_SERVICE_NAME,
		ID:   c.id,
		Tags: []string{c.id},
		//Address: "10.10.10.25",
		//Port:    50003,
		Check: &api.AgentServiceCheck{
			DeregisterCriticalServiceAfter: model.APP_DEREGESTER_CRITICAL_TTL.String(),
			TTL: model.APP_SERVICE_TTL.String(),
		},
	}

	if err = c.agent.ServiceRegister(as); err != nil {
		return model.NewAppError("Cluster.RegisterService", "cluster.consul.service_register.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}

	var checks map[string]*api.AgentCheck
	if checks, err = c.agent.Checks(); err != nil {
		return model.NewAppError("Cluster.RegisterService", "cluster.consul.service_check.app_error", nil,
			fmt.Sprintf("failed to query checks from consul agent: %v", err.Error()), http.StatusInternalServerError)
	}

	var serviceCheck *api.AgentCheck
	for _, check := range checks {
		if check.ServiceID == c.id {
			serviceCheck = check
		}
	}

	if serviceCheck == nil {
		return model.NewAppError("Cluster.RegisterService", "cluster.consul.service_find.app_error", nil,
			"failed to find service after registration at consul", http.StatusInternalServerError)
	}
	c.checkId = serviceCheck.CheckID
	c.update()

	wlog.Info(fmt.Sprintf("started consul service id: %s", c.id))

	go c.updateTTL()

	return nil
}

func (c *consul) update() {
	ok, err := c.check()
	if !ok {
		if agentErr := c.agent.FailTTL(c.checkId, err.Error()); agentErr != nil {
			wlog.Error(agentErr.Error())
		}
	} else {
		if agentErr := c.agent.PassTTL(c.checkId, "I'm ready..."); agentErr != nil {
			wlog.Error(agentErr.Error())
		}
	}
}

func (c *consul) updateTTL() {
	defer wlog.Info("stopped consul checker")

	ticker := time.NewTicker(model.APP_SERVICE_TTL / 2)
	for {
		select {
		case <-c.stop:
			return
		case <-ticker.C:
			c.update()
		}
	}
}

func (c *consul) Shutdown() {
	close(c.stop)
	c.agent.ServiceDeregister(c.id)
}

func (c *consul) GetValueByKey(key string) string {
	kvp, _, _ := c.kv.Get(key, nil)
	return string(kvp.Value)
}

func (c *consul) SaveValue(key, value string) {
	c.kv.Put(&api.KVPair{Key: key, Value: []byte(value)}, nil)
}
