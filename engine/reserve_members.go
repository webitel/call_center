package engine

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
	"time"
)

func (e *EngineImp) ReserveMembers() {
	if !e.app.IsReady() {
		wlog.Error("app not ready to reserve members")
		time.Sleep(time.Second * 5)
		return
	}

	cnt, err := e.store.Member().ReserveMembersByNode(e.nodeId)
	if err != nil {
		wlog.Error(err.Error())
		time.Sleep(time.Second * 5)
	} else {
		if cnt > 0 {
			wlog.Debug(fmt.Sprintf("reserve %v members", cnt))
		}
	}
}

func (e *EngineImp) UnReserveMembers() {
	cnt, err := e.store.Member().UnReserveMembersByNode(e.nodeId, model.MEMBER_CAUSE_SYSTEM_SHUTDOWN)
	if err != nil {
		wlog.Error(err.Error())
	} else {
		if cnt > 0 {
			wlog.Debug(fmt.Sprintf("un reserve %v members", cnt))
		}
	}
}
