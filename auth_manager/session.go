package auth_manager

import "github.com/webitel/call_center/model"

func (am *authManager) GetSession(token string) (*model.Session, *model.AppError) {

	if v, ok := am.session.Get(token); ok && false {
		return v.(*model.Session), nil
	}

	client, err := am.getAuthClient()
	if err != nil {
		return nil, err
	}

	session, err := client.GetSession(token)
	if err != nil {
		return nil, err
	}
	am.session.AddWithDefaultExpires(token, session)

	return session, nil
}
