package call_manager

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
)

func (cm *CallManagerImpl) handleCallAction(data model.CallActionData) {
	var call *CallImpl
	action := data.GetEvent()
	if v, ok := cm.GetCall(data.Id); ok {
		call = v.(*CallImpl)
	}

	switch action.(type) {
	case *model.CallActionRinging:
		callRinging := action.(*model.CallActionRinging)
		if callRinging.Direction == model.CALL_DIRECTION_INBOUND {
			//FIXME NOT IMPLEMENT
		} else if call != nil {
			call.setRinging(callRinging)
		} else {
			//FIXME ?
		}

	case *model.CallActionJoinQueue:
		callJoin := action.(*model.CallActionJoinQueue)
		if callJoin.Direction == model.CALL_DIRECTION_INBOUND {
			cm.joinInboundCall(callJoin)
		} else if callJoin.Direction == model.CALL_DIRECTION_OUTBOUND && call != nil {
			call.setJoinQueue(callJoin)
		} else {
			//FIXME ?
		}

	case *model.CallActionLeavingQueue:
		if call == nil {
			return
		}
		call.setLeavingQueue(action.(*model.CallActionLeavingQueue))

	case *model.CallActionActive:
		if call == nil {
			return
		}
		call.setActive(action.(*model.CallActionActive))

	case *model.CallActionBridge:
		if call == nil {
			return
		}
		call.setBridge(action.(*model.CallActionBridge))

	case *model.CallActionHold:
		if call == nil {
			return
		}
		call.setHold(action.(*model.CallActionHold))

	case *model.CallActionHangup:
		if call == nil {
			return
		}
		call.setHangup(action.(*model.CallActionHangup))

	default:
		wlog.Warn(fmt.Sprintf("call %s not have handler action %s", data.Id, data.Action))
	}
}
