package engine

import (
	"fmt"
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
	"time"
)

func (e *EngineImp) ReserveMembers() {
	cnt, err := e.store.Member().ReserveMembersByNode(e.nodeId)
	if err != nil {
		mlog.Error(err.Error())
		time.Sleep(time.Second * 5)
	} else {
		if cnt > 0 {
			mlog.Debug(fmt.Sprintf("Reserve %v members", cnt))
		}
	}
}

func (e *EngineImp) UnReserveMembers() {
	cnt, err := e.store.Member().UnReserveMembersByNode(e.nodeId, model.MEMBER_CAUSE_SYSTEM_SHUTDOWN)
	if err != nil {
		mlog.Error(err.Error())
	} else {
		if cnt > 0 {
			mlog.Debug(fmt.Sprintf("Un reserve %v members", cnt))
		}
	}
}
