package app

import (
	"github.com/webitel/call_center/model"
	"net/http"
)

func (app *App) GetAgentById(agentId int64) (*model.Agent, *model.AppError) {
	if result := <-app.Store.Agent().Get(agentId); result.Err != nil {
		return nil, result.Err
	} else {
		return result.Data.(*model.Agent), nil
	}
}

func (app *App) SetAgentStateById(agentId int64, state string) *model.AppError {

	agent, err := app.GetAgentById(agentId)
	if err != nil {
		return err
	}

	if agentObj, err := app.agentManager.GetAgent(agentId, agent.UpdatedAt); err != nil {
		return err
	} else {
		return app.agentManager.SetAgentState(agentObj, state, 0)
	}
}

func (app *App) SetAgentLogin(agentId int64) *model.AppError {
	var agent *model.Agent
	var err *model.AppError

	if agent, err = app.GetAgentById(agentId); err != nil {
		return err
	}

	if agent.Status == model.AGENT_STATE_WAITING {
		return model.NewAppError("SetAgentLogin", "app.agent.set_login.agent_logged", nil, "", http.StatusBadRequest)
	}

	if agentObj, err := app.agentManager.GetAgent(agentId, agent.UpdatedAt); err != nil {
		return err
	} else {
		return app.agentManager.SetAgentStatus(agentObj, &model.AgentStatus{
			Status: model.AGENT_STATE_WAITING,
		})
	}
}

func (app *App) SetAgentLogout(agentId int64) *model.AppError {
	var agent *model.Agent
	var err *model.AppError

	if agent, err = app.GetAgentById(agentId); err != nil {
		return err
	}

	if agent.Status == model.AGENT_STATUS_LOGGED_OUT {
		return model.NewAppError("SetAgentLogout", "app.agent.set_logout.agent_logged_out", nil, "", http.StatusBadRequest)
	}

	if agentObj, err := app.agentManager.GetAgent(agentId, agent.UpdatedAt); err != nil {
		return err
	} else {
		return app.agentManager.SetAgentStatus(agentObj, &model.AgentStatus{
			Status: model.AGENT_STATE_LOGOUT,
		})
	}
}
