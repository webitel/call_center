package engine

import (
	"fmt"
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
	"time"
)

func (e *EngineImp) ReserveMembers() {
	result := <-e.store.Member().ReserveMembersByNode(e.nodeId)
	if result.Err != nil {
		mlog.Error(result.Err.Error())
		time.Sleep(time.Second * 5)
	} else {
		if result.Data.(int64) > 0 {
			mlog.Debug(fmt.Sprintf("Reserve %v members", result.Data))
		}
	}
}

func (e *EngineImp) UnReserveMembers() {
	result := <-e.store.Member().UnReserveMembersByNode(e.nodeId, model.MEMBER_CAUSE_SYSTEM_SHUTDOWN)
	if result.Err != nil {
		mlog.Error(result.Err.Error())
	} else {
		if result.Data.(int64) > 0 {
			mlog.Debug(fmt.Sprintf("Un reserve %v members", result.Data))
		}
	}
}
