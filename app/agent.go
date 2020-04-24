package app

import (
	"github.com/webitel/call_center/model"
	"net/http"
)

func (app *App) GetAgentById(agentId int) (*model.Agent, *model.AppError) {
	if a, err := app.Store.Agent().Get(agentId); err != nil {
		return nil, err
	} else {
		return a, nil
	}
}

func (app *App) SetAgentOnline(agentId int, channels []string, onDemand bool) (*model.AgentOnlineData, *model.AppError) {
	var agent *model.Agent
	var err *model.AppError

	if agent, err = app.GetAgentById(agentId); err != nil {
		return nil, err
	}

	if agent.Status == model.AgentStatusOnline {
		return nil, model.NewAppError("SetAgentLogin", "app.agent.set_login.agent_logged", nil, "", http.StatusBadRequest)
	}

	if agentObj, err := app.agentManager.GetAgent(agentId, agent.UpdatedAt); err != nil {
		return nil, err
	} else {
		return app.agentManager.SetOnline(agentObj, channels, onDemand)
	}
}

func (app *App) SetAgentLogout(agentId int) *model.AppError {
	var agent *model.Agent
	var err *model.AppError

	if agent, err = app.GetAgentById(agentId); err != nil {
		return err
	}

	if agent.Status == model.AgentStatusOffline {
		return model.NewAppError("SetAgentLogout", "app.agent.set_logout.agent_logged_out", nil, "", http.StatusBadRequest)
	}

	if agentObj, err := app.agentManager.GetAgent(agentId, agent.UpdatedAt); err != nil {
		return err
	} else {
		return app.agentManager.SetOffline(agentObj)
	}
}

func (app *App) SetAgentPause(agentId int, payload *string, timeout *int) *model.AppError {
	var agent *model.Agent
	var err *model.AppError

	if agent, err = app.GetAgentById(agentId); err != nil {
		return err
	}

	if agentObj, err := app.agentManager.GetAgent(agentId, agent.UpdatedAt); err != nil {
		return err
	} else {
		return app.agentManager.SetPause(agentObj, payload, timeout)
	}
}

func (app *App) WaitingAgentChannel(agentId int, channel string) (int64, *model.AppError) {
	var agent *model.Agent
	var err *model.AppError

	if agent, err = app.GetAgentById(agentId); err != nil {
		return 0, err
	}

	if agentObj, err := app.agentManager.GetAgent(agentId, agent.UpdatedAt); err != nil {
		return 0, err
	} else {
		return app.dialing.Manager().SetAgentWaitingChannel(agentObj, channel)
	}
}
