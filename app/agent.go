package app

import (
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
	"net/http"
)

func (app *App) GetAgentById(agentId int) (*model.Agent, *model.AppError) {
	if a, err := app.Store.Agent().Get(agentId); err != nil {
		return nil, err
	} else {
		return a, nil
	}
}

func (app *App) SetAgentOnline(agentId int, onDemand bool) (*model.AgentOnlineData, *model.AppError) {
	var agent *model.Agent
	var err *model.AppError

	if agent, err = app.GetAgentById(agentId); err != nil {
		return nil, err
	}

	if agent.Status == model.AgentStatusOnline && agent.OnDemand == onDemand {
		return nil, model.NewAppError("SetAgentLogin", "app.agent.set_login.agent_logged", nil, "", http.StatusBadRequest)
	}

	if agentObj, err := app.agentManager.GetAgent(agentId, agent.UpdatedAt); err != nil {
		return nil, err
	} else {
		return app.agentManager.SetOnline(agentObj, onDemand)
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

	if chs, _ := app.Store.Agent().GetNoAnswerChannels(agentId, []int{model.QueueTypeProgressiveCall}); chs != nil {
		//TODO Task & chat
		app.hangupNoAnswerChannels(chs)
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
	var allow bool

	if agent, err = app.GetAgentById(agentId); err != nil {
		return err
	}

	if agent.Status == model.AgentStatusPause && getString(agent.StatusPayload) == getString(payload) {
		return model.NewAppError("SetAgentPause", "app.agent.set_pause.payload", nil, "already payload", http.StatusBadRequest)
	}

	allow, err = app.Store.Agent().CheckAllowPause(agent.DomainId, agentId)
	if err != nil {
		return err
	}

	if !allow {
		return model.NewAppError("SetAgentPause", "app.agent.set_pause.not_allow", nil, "Toy can't take a pause right now", http.StatusBadRequest)
	}

	if chs, _ := app.Store.Agent().GetNoAnswerChannels(agentId, nil); chs != nil {
		//TODO Task & chat
		app.hangupNoAnswerChannels(chs)
	}

	if agentObj, err := app.agentManager.GetAgent(agentId, agent.UpdatedAt); err != nil {
		return err
	} else {
		return app.agentManager.SetPause(agentObj, payload, timeout)
	}
}

func (app *App) hangupNoAnswerChannels(chs []*model.CallNoAnswer) {
	for _, ch := range chs {
		if err := app.callManager.HangupById(ch.Id, ch.AppId); err != nil {
			wlog.Error(err.Error())
		}
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

func (app *App) AcceptAgentTask(attemptId int64) *model.AppError {
	return app.dialing.Manager().AcceptAgentTask(attemptId)
}

func (app *App) CloseAgentTask(attemptId int64) *model.AppError {
	return app.dialing.Manager().CloseAgentTask(attemptId)
}

func getString(p *string) string {
	if p == nil {
		return ""
	}

	return *p
}
