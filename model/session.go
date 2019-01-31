package model

const (
	SESSION_CACHE_SIZE = 35000
)

type Session struct {
	Id     string `json:"id"`
	Token  string `json:"token"`
	UserId string `json:"user_id"`
}

func (self *Session) IsExpired() bool {
	//TODO
	return false
}
