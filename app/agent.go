package app

import (
	"context"
	"maps"
	"net/http"
	"strconv"

	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/model"
	"github.com/webitel/engine/pkg/wbt/gen/workflow"
	"github.com/webitel/wlog"
)

func (app *App) GetAgentById(agentId int) (*model.Agent, *model.AppError) {
	if a, err := app.Store.Agent().Get(agentId); err != nil {
		return nil, err
	} else {
		return a, nil
	}
}

func (app *App) AgentGoOnline(ctx context.Context, r *model.AgentOnlineRequest) (*model.AgentOnlineData, *model.AppError) {
	agentData, err := app.Store.Agent().SetOnlineAtomic(ctx, r)
	if err != nil {
		return nil, err
	}

	ad := model.AgentOnlineData{
		Timestamp:    agentData.Timestamp,
		Channel:      agentData.Channels,
		StatusPreset: &agentData.StatusPreset,
	}

	agentObj := app.agentManager.PutAgentCache(&agentData.Agent)

	agentObj.SetOnDemand(r.OnDemand)
	agentObj.StoreStatus(model.CreateAgentStatus(model.AgentStatusOnline, model.WithStatusPreset(ad.StatusPreset)))

	event := agent_manager.NewAgentEventOnlineStatus(agentObj, &ad, r.OnDemand)

	if err = app.agentManager.PublishAgentStatusChangeEvent(agentObj, event); err != nil {
		agentObj.Log().Error("publishing agent online status change event to broker", wlog.Err(err))
	}

	app.Queue().Manager().AgentTeamHook(model.HookAgentStatus, agentObj, agentData.Agent.TeamUpdatedAt)

	return &ad, nil
}

func (app *App) SetAgentLogout(agentId int) *model.AppError {
	agent, err := app.GetAgentById(agentId)
	if err != nil {
		return err
	}

	if agent.Offline() {
		return model.NewAppError("SetAgentLogout", "app.agent.set_logout.agent_logged_out", nil, "", http.StatusBadRequest)
	}

	if chs, _ := app.Store.Agent().GetNoAnswerChannels(agentId, []int{model.QueueTypeProgressiveCall}); chs != nil {
		//TODO Task & chat
		app.hangupNoAnswerChannels(chs)
	}

	agentObj, err := app.agentManager.GetAgent(agentId, agent.UpdatedAt)
	if err != nil {
		return err
	}

	err = app.agentManager.SetOffline(agentObj, nil)
	if err != nil {
		return err
	}

	app.Queue().Manager().AgentTeamHook(model.HookAgentStatus, agentObj, agent.TeamUpdatedAt)

	return nil
}

func (app *App) SetAgentPause(agentId int, payload, statusComment *string, timeout *int) *model.AppError {
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
		return model.NewAppError("SetAgentPause", "app.agent.set_pause.not_allow", nil, "You can't take a pause right now", http.StatusBadRequest)
	}

	if chs, _ := app.Store.Agent().GetNoAnswerChannels(agentId, nil); chs != nil {
		//TODO Task & chat
		app.hangupNoAnswerChannels(chs)
	}

	if agentObj, err := app.agentManager.GetAgent(agentId, agent.UpdatedAt); err != nil {
		return err
	} else {
		err = app.agentManager.SetPause(agentObj, payload, statusComment, timeout)
		if err != nil {
			return err
		}
		app.Queue().Manager().AgentTeamHook(model.HookAgentStatus, agentObj, agent.TeamUpdatedAt)
		return nil
	}
}

func (app *App) SetAgentBreakOut(agent agent_manager.AgentObject) *model.AppError {
	err := app.agentManager.SetBreakOut(agent)
	if err != nil {
		return err
	}
	app.Queue().Manager().AgentTeamHook(model.HookAgentStatus, agent, agent.TeamUpdatedAt())

	return nil
}

func (app *App) hangupNoAnswerChannels(chs []*model.CallNoAnswer) {
	for _, ch := range chs {
		if ch.Id != nil && ch.AppId != nil {
			if err := app.callManager.HangupById(*ch.Id, *ch.AppId); err != nil {
				app.Log.Error(err.Error(),
					wlog.Err(err),
					wlog.String("call_id", *ch.Id),
				)
			}
		} else {
			// low cps race call DEV-4783
			att, ok := app.Queue().Manager().GetAttempt(ch.AttemptId)
			if ok {
				att.SetCancel()
			}
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

func (app *App) RunTeamTrigger(ctx context.Context, domainId int64, userId int64, triggerId int32, vars map[string]string) (string, *model.AppError) {
	data, appErr := app.Store.Agent().AgentTriggerJob(ctx, domainId, userId, triggerId)
	if appErr != nil {
		return "", appErr
	}

	if vars == nil {
		vars = make(map[string]string)
	}

	maps.Copy(vars, data.Variables)

	vars["agent_id"] = strconv.Itoa(int(data.AgentId))
	vars["user_id"] = strconv.Itoa(int(userId))
	vars["email"] = data.Email
	vars["extension"] = data.Extension
	vars["agent_name"] = data.Name

	jobId, err := app.flowManager.Queue().StartFlow(&workflow.StartFlowRequest{
		SchemaId:  data.SchemaId,
		DomainId:  domainId,
		Variables: vars,
	})
	if err != nil {
		return "", model.NewAppError("RunTeamTrigger", "app.fm.start_flow", nil, err.Error(), http.StatusInternalServerError)
	}

	return jobId, nil
}

func (app *App) hookAutoOfflineAgent(agent agent_manager.AgentObject) {
	app.Queue().Manager().AgentTeamHook(model.HookAgentStatus, agent, agent.TeamUpdatedAt())
}

func getString(p *string) string {
	if p == nil {
		return ""
	}

	return *p
}
