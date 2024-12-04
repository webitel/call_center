package engine

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
	"time"
)

func (e *EngineImp) ReserveMembers() {
	if !e.app.IsReady() {
		e.log.Error("app not ready to reserve members")
		time.Sleep(time.Second * 5)
		return
	}
	st := time.Now()
	cnt, err := e.store.Member().ReserveMembersByNode(e.nodeId, e.enableOmnichannel)
	if err != nil {
		e.log.Error(err.Error(),
			wlog.Err(err),
		)
		time.Sleep(time.Second * 5)
	} else {
		if cnt > 0 {
			e.log.Debug(fmt.Sprintf("reserve %v members", cnt))
		}
		diff := time.Now().Sub(st)
		if diff > time.Second*2 {
			e.log.Debug(fmt.Sprintf("distribute time: %s", time.Now().Sub(st)))
		}
	}
}

func (e *EngineImp) UnReserveMembers() {
	cnt, err := e.store.Member().UnReserveMembersByNode(e.nodeId, model.MEMBER_CAUSE_SYSTEM_SHUTDOWN)
	if err != nil {
		e.log.Error(err.Error(),
			wlog.Err(err),
		)
	} else {
		if cnt > 0 {
			e.log.Debug(fmt.Sprintf("unreserve %v members", cnt))
		}
	}
}

func (e *EngineImp) CleanAllAttempts() {
	err := e.store.Member().CleanAttempts(e.nodeId)
	if err != nil {
		e.log.Error(err.Error(),
			wlog.Err(err),
		)
	}
}
