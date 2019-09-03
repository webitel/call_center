package model

import (
	"testing"
)

var (
	testSession = &Session{
		Id:       "test",
		DomainId: 1,
		Expire:   1,
		UserId:   1,
		RoleIds:  nil,
		Token:    "",
		Scopes: []SessionPermission{
			{
				Id:     0,
				Name:   "test",
				Abac:   false,
				Obac:   true,
				Rbac:   false,
				Access: PERMISSION_ACCESS_READ.Value() | PERMISSION_ACCESS_CREATE.Value(),
			},
		},
	}
)

func TestModelSession(t *testing.T) {
	testScopeAllowPermission(t)
}

func testScopeAllowPermission(t *testing.T) {

	if !testSession.GetPermission("test").CanRead() {
		t.Errorf("CanRead")
	}

	if !testSession.GetPermission("test").CanCreate() {
		t.Errorf("CanCreate")
	}

	if testSession.GetPermission("test").CanDelete() {
		t.Errorf("CanDelete")
	}

	if testSession.GetPermission("test1").CanDelete() {
		t.Errorf("custum permmision")
	}
}
