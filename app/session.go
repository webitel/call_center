package app

import (
	"github.com/pkg/errors"
	"github.com/webitel/call_center/model"
	"net/http"
)

func (a *App) GetSession(token string) (*model.Session, *model.AppError) {

	session, err := a.authManager.GetSession(token)
	if err != nil {
		return nil, err
	}

	if session == nil {
		return nil, model.NewAppError("GetSession", "api.context.invalid_token.error", map[string]interface{}{"Token": token, "Error": ""}, "", http.StatusUnauthorized)
	}

	return session, nil
}

func (a *App) createSessionForUserAccessToken(tokenString string) (*model.Session, *model.AppError) {
	err := errors.New("TODO")
	return nil, model.NewAppError(
		"createSessionForUserAccessToken",
		"app.user_access_token.invalid_or_missing",
		nil,
		err.Error(), http.StatusUnauthorized)
}
