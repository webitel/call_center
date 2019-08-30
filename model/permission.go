package model

const (
	PERMISSION_SCOPE_CALENDAR = "calendars"
)

type PermissionAccess uint32

const (
	PERMISSION_ACCESS_CREATE PermissionAccess = iota
	PERMISSION_ACCESS_READ
	PERMISSION_ACCESS_UPDATE
	PERMISSION_ACCESS_DELETE
)

func (p PermissionAccess) Value() uint32 {
	return [...]uint32{8, 4, 2, 1}[p]
}
func (p PermissionAccess) Name() string {
	return [...]string{"create", "read", "update", "delete"}[p]
}
