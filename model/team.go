package model

type Team struct {
	Id          int64   `json:"id" db:"id"`
	DomainId    int64   `json:"domain_id" db:"domain_id"`
	Name        string  `json:"name" db:"name"`
	Strategy    string  `json:"strategy" db:"strategy"`
	Description *string `json:"description" db:"description"`
	UpdatedAt   int64   `json:"updated_at" db:"updated_at"`

	CallTimeout       uint16 `json:"call_timeout" db:"call_timeout"`
	MaxNoAnswer       uint16 `json:"max_no_answer" db:"max_no_answer"`
	WrapUpTime        uint16 `json:"wrap_up_time" db:"wrap_up_time"`
	RejectDelayTime   uint16 `json:"reject_delay_time" db:"reject_delay_time"`
	BusyDelayTime     uint16 `json:"busy_delay_time" db:"busy_delay_time"`
	NoAnswerDelayTime uint16 `json:"no_answer_delay_time" db:"no_answer_delay_time"`
}
