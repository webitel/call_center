package dialing

import "github.com/webitel/call_center/model"

type OutboundDialing struct {
	members chan *model.MemberJob
}

func NewOutboundDialing() *OutboundDialing {
	return &OutboundDialing{
		members: make(chan *model.MemberJob),
	}
}

func (o *OutboundDialing) AddMember() {

}
