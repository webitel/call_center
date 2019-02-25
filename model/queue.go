package model

type Queue struct {
	Id       int  `json:"id"`
	Type     int  `json:"type"`
	Strategy int  `json:"strategy"`
	Enabled  bool `json:"enabled"`

	MaxCalls int `json:"max_calls"`
}
