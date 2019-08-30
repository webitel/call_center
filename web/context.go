package web

import (
	goi18n "github.com/nicksnyder/go-i18n/i18n"
	"github.com/webitel/call_center/app"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"net/http"
)

type Context struct {
	App           *app.App
	Log           *wlog.Logger
	Session       model.Session
	Err           *model.AppError
	T             goi18n.TranslateFunc
	RequestId     string
	IpAddress     string
	Path          string
	siteURLHeader string
	Params        *Params
}

func (c *Context) LogError(err *model.AppError) {
	// Filter out 404s, endless reconnects and browser compatibility errors
	if err.StatusCode == http.StatusNotFound {
		c.LogDebug(err)
	} else {
		c.Log.Error(
			err.SystemMessage(utils.TDefault),
			wlog.String("err_where", err.Where),
			wlog.Int("http_code", err.StatusCode),
			wlog.String("err_details", err.DetailedError),
		)
	}
}

func (c *Context) LogInfo(err *model.AppError) {
	// Filter out 401s
	if err.StatusCode == http.StatusUnauthorized {
		c.LogDebug(err)
	} else {
		c.Log.Info(
			err.SystemMessage(utils.TDefault),
			wlog.String("err_where", err.Where),
			wlog.Int("http_code", err.StatusCode),
			wlog.String("err_details", err.DetailedError),
		)
	}
}

func (c *Context) LogDebug(err *model.AppError) {
	c.Log.Debug(
		err.SystemMessage(utils.TDefault),
		wlog.String("err_where", err.Where),
		wlog.Int("http_code", err.StatusCode),
		wlog.String("err_details", err.DetailedError),
	)
}

func (c *Context) SessionRequired() {
	if c.Session.UserId < 1 {
		c.Err = model.NewAppError("", "api.context.session_expired.app_error", nil, "UserRequired", http.StatusUnauthorized)
		return
	}
}

func (c *Context) RequireId() *Context {
	if c.Err != nil {
		return c
	}

	if c.Params.Id == 0 {
		c.SetInvalidUrlParam("id")
	}
	return c
}

func (c *Context) SetInvalidUrlParam(parameter string) {
	c.Err = NewInvalidUrlParamError(parameter)
}

func (c *Context) SetPermissionError(permission model.SessionPermission, access model.PermissionAccess) {
	c.Err = c.App.MakePermissionError(&c.Session, permission, access)
}

func NewInvalidUrlParamError(parameter string) *model.AppError {
	err := model.NewAppError("Context", "api.context.invalid_url_param.app_error", map[string]interface{}{"Name": parameter}, "", http.StatusBadRequest)
	return err
}

func (c *Context) SetInvalidParam(parameter string) {
	c.Err = NewInvalidParamError(parameter)
}

func NewInvalidParamError(parameter string) *model.AppError {
	err := model.NewAppError("Context", "api.context.invalid_body_param.app_error", map[string]interface{}{"Name": parameter}, "", http.StatusBadRequest)
	return err
}
