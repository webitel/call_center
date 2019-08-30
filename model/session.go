package model

import "net/http"

const (
	SESSION_CACHE_SIZE = 35000
)

type AuthClient interface {
	Name() string
	Close() *AppError
	Ready() bool

	GetSession(token string) (*Session, *AppError)
}

type SessionPermission struct {
	Id     int    `json:"id"`
	Name   string `json:"name"`
	Abac   bool   `json:"abac"`
	Obac   bool   `json:"obac"`
	Rbac   bool   `json:"rbac"`
	Access uint32 `json:"access"`
}

type Session struct {
	Id       string  `json:"id"`
	DomainId int64   `json:"domain_id"`
	Expire   int64   `json:"expire"`
	UserId   int64   `json:"user_id"`
	RoleIds  []int64 `json:"role_ids"`

	Token  string `json:"token"`
	Scopes []SessionPermission
}

func NotAllowPermission(name string) SessionPermission {
	return SessionPermission{
		Id:     0,
		Name:   name,
		Abac:   true,
		Obac:   true,
		Rbac:   true,
		Access: 0,
	}
}

func (s SessionPermission) CanCreate() bool {
	if s.Obac || s.Rbac {
		return s.Access&PERMISSION_ACCESS_CREATE.Value() == PERMISSION_ACCESS_CREATE.Value()
	}
	return !s.Rbac && !s.Obac
}

func (s SessionPermission) CanRead() bool {
	if s.Obac || s.Rbac {
		return s.Access&PERMISSION_ACCESS_READ.Value() == PERMISSION_ACCESS_READ.Value()
	}
	return !s.Rbac && !s.Obac
}

func (s SessionPermission) CanUpdate() bool {
	if s.Obac || s.Rbac {
		return s.Access&PERMISSION_ACCESS_UPDATE.Value() == PERMISSION_ACCESS_UPDATE.Value()
	}
	return !s.Rbac && !s.Obac
}

func (s SessionPermission) CanDelete() bool {
	if s.Obac || s.Rbac {
		return s.Access&PERMISSION_ACCESS_DELETE.Value() == PERMISSION_ACCESS_DELETE.Value()
	}
	return !s.Rbac && !s.Obac
}

func (self *Session) HasLicense() bool {
	return true
}

func (self *Session) GetPermission(name string) SessionPermission {
	for _, v := range self.Scopes {
		if v.Name == name {
			return v
		}
	}
	return NotAllowPermission(name)
}

func (self *Session) IsExpired() bool {
	return self.Expire < GetMillis()
}

func (self *Session) Trace() map[string]interface{} {
	return map[string]interface{}{"id": self.Id, "domain_id": self.DomainId}
}

func (self *Session) IsValid() *AppError {

	if len(self.Id) < 1 {
		return NewAppError("Session.IsValid", "model.session.is_valid.id.app_error", self.Trace(), "", http.StatusBadRequest)
	}

	if self.DomainId < 1 {
		return NewAppError("Session.IsValid", "model.session.is_valid.domain_id.app_error", self.Trace(), "", http.StatusBadRequest)
	}

	//TODO
	return nil
}
