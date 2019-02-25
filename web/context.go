package web

import (
	goi18n "github.com/nicksnyder/go-i18n/i18n"
	"github.com/webitel/call_center/app"
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/utils"
	"net/http"
)

type Context struct {
	App           *app.App
	Log           *mlog.Logger
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
			mlog.String("err_where", err.Where),
			mlog.Int("http_code", err.StatusCode),
			mlog.String("err_details", err.DetailedError),
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
			mlog.String("err_where", err.Where),
			mlog.Int("http_code", err.StatusCode),
			mlog.String("err_details", err.DetailedError),
		)
	}
}

func (c *Context) LogDebug(err *model.AppError) {
	c.Log.Debug(
		err.SystemMessage(utils.TDefault),
		mlog.String("err_where", err.Where),
		mlog.Int("http_code", err.StatusCode),
		mlog.String("err_details", err.DetailedError),
	)
}

func (c *Context) SessionRequired() {
	if len(c.Session.UserId) == 0 {
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

func NewInvalidUrlParamError(parameter string) *model.AppError {
	err := model.NewAppError("Context", "api.context.invalid_url_param.app_error", map[string]interface{}{"Name": parameter}, "", http.StatusBadRequest)
	return err
}
