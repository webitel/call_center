package grpc

import (
	"context"
	"github.com/webitel/call_center/external_commands/grpc/auth"
	"github.com/webitel/call_center/model"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/connectivity"
	"google.golang.org/grpc/status"
	"net/http"
)

type authConnection struct {
	name   string
	host   string
	client *grpc.ClientConn
	api    auth.SAClient
}

func NewAuthServiceConnection(name, url string) (*authConnection, *model.AppError) {
	var err error
	connection := &authConnection{
		name: name,
		host: url,
	}

	connection.client, err = grpc.Dial(url, grpc.WithInsecure(), grpc.WithBlock(), grpc.WithTimeout(CONNECTION_TIMEOUT))

	if err != nil {
		return nil, model.NewAppError("NewAuthServiceConnection", "grpc.create_connection.app_error", nil, err.Error(), http.StatusInternalServerError)
	}

	connection.api = auth.NewSAClient(connection.client)

	return connection, nil
}

func (ac *authConnection) GetSession(token string) (*model.Session, *model.AppError) {

	resp, err := ac.api.Current(context.TODO(), &auth.VerifyTokenRequest{token})

	if err != nil {
		if status.Code(err) == codes.Unauthenticated {
			return nil, model.NewAppError("AuthConnection.GetSession", "grpc.get_session.app_error", nil, err.Error(), http.StatusForbidden)
		}
		return nil, model.NewAppError("AuthConnection.GetSession", "grpc.get_session.app_error", nil, err.Error(), http.StatusInternalServerError)
	}

	if resp.Session == nil {
		return nil, model.NewAppError("AuthConnection.GetSession", "grpc.get_session.app_error", nil, "Not found", http.StatusForbidden)
	}

	session := &model.Session{
		Id:       resp.Session.Uuid,
		UserId:   resp.Session.UserId,
		DomainId: resp.Session.Dc,
		Expire:   resp.Session.ExpiresAt,
		Token:    token,
		Scopes:   transformScopes(resp.Scope),
		RoleIds:  transformRoles(resp.Roles),
	}
	return session, nil
}

func (ac *authConnection) Ready() bool {
	switch ac.client.GetState() {
	case connectivity.Idle, connectivity.Ready:
		return true
	}
	return false
}

func (ac *authConnection) Name() string {
	return ac.name
}

func (ac *authConnection) Close() *model.AppError {
	err := ac.client.Close()
	if err != nil {
		return model.NewAppError("AuthConnection", "grpc.close_connection.app_error", nil, err.Error(), http.StatusInternalServerError)
	}
	return nil
}

func transformScopes(src []*auth.AccessScope) []model.SessionPermission {
	dst := make([]model.SessionPermission, 0, len(src))
	for _, v := range src {
		dst = append(dst, model.SessionPermission{
			Id:     int(v.Id),
			Name:   v.Class,
			Abac:   v.Abac,
			Obac:   v.Obac,
			Rbac:   v.Rbac,
			Access: v.Access,
		})
	}
	return dst
}

func transformRoles(src map[string]int64) []int {
	dst := make([]int, 0, len(src))
	for _, v := range src {
		dst = append(dst, int(v))
	}
	return dst
}
