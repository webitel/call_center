package app

import (
	"github.com/pkg/errors"
	"github.com/webitel/call_center/model"
	"net/http"
)

func (a *App) GetSession(token string) (*model.Session, *model.AppError) {

	var session *model.Session
	var err *model.AppError

	if ts, ok := a.sessionCache.Get(token); ok {
		session = ts.(*model.Session)
	}

	if session == nil {
		if session, err = a.Srv.Store.Session().Get(token); err == nil {

			if session != nil {
				if session.Token != token {
					return nil, model.NewAppError("GetSession", "api.context.invalid_token.error", map[string]interface{}{"Token": token, "Error": ""}, "", http.StatusUnauthorized)
				}

				if !session.IsExpired() {
					a.AddSessionToCache(session)
				}
			}
		} else if err.StatusCode == http.StatusInternalServerError {
			return nil, err
		}
	}

	if session == nil {
		var err *model.AppError
		session, err = a.createSessionForUserAccessToken(token)
		if err != nil {
			detailedError := ""
			statusCode := http.StatusUnauthorized
			if err.Id != "app.user_access_token.invalid_or_missing" {
				detailedError = err.Error()
				statusCode = err.StatusCode
			}
			return nil, model.NewAppError("GetSession", "api.context.invalid_token.error", map[string]interface{}{"Token": token}, detailedError, statusCode)
		}
	}

	return session, nil
}

func (a *App) AddSessionToCache(session *model.Session) {
	a.sessionCache.AddWithExpiresInSecs(session.Token, session, int64(*a.Config().ServiceSettings.SessionCacheInMinutes*60))
}

func (a *App) createSessionForUserAccessToken(tokenString string) (*model.Session, *model.AppError) {
	err := errors.New("TODO")
	return nil, model.NewAppError(
		"createSessionForUserAccessToken",
		"app.user_access_token.invalid_or_missing",
		nil,
		err.Error(), http.StatusUnauthorized)
}
