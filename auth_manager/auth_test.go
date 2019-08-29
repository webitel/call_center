package auth_manager

import (
	"github.com/webitel/call_center/cluster"
	"github.com/webitel/call_center/model"
	"testing"
)

const (
	TEST_NODE_ID = "call-center-test"
	TOKEN        = "USER_TOKEN"
)

func TestAuthManager(t *testing.T) {
	t.Log("AuthManager")

	sd, err := cluster.NewServiceDiscovery(AUTH_SERVICE_NAME, func() (b bool, appError *model.AppError) {
		return true, nil
	})
	if err != nil {
		panic(err.Error())
	}

	am := NewAuthManager(sd)
	am.Start()
	defer am.Stop()

	testGetSession(t, TOKEN, am)
}

func testGetSession(t *testing.T, token string, am AuthManager) {

	session, err := am.GetSession(token)
	if err != nil {
		t.Errorf("get session \"%s\" error: %s", token, err.Error())
		return
	}

	if session == nil {
		t.Errorf("get session \"%s\" is nil", token)
		return
	}

	if err = session.IsValid(); err != nil {
		t.Errorf("bad session \"%s\": %v", token, err.Error())
		return
	}
}
