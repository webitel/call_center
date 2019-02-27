package dialing

import (
	"fmt"
	"github.com/webitel/call_center/model"
)

type Attempt struct {
	member *model.MemberAttempt
}

func NewAttempt(member *model.MemberAttempt) *Attempt {
	return &Attempt{
		member: member,
	}
}

func (a *Attempt) Name() string {
	return fmt.Sprintf("%v", a.member.MemberId)
}
