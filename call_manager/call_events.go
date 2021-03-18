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

	//wlog.Debug(fmt.Sprintf("call %s receive event %s", data.Id, data.Event))

	switch action.(type) {
	case *model.CallActionRinging:
		callRinging := action.(*model.CallActionRinging)
		if call == nil {
			return
		}
		call.setRinging(callRinging)

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

	case *model.CallActionAMD:
		if call == nil {
			return
		}
		call.setAmd(action.(*model.CallActionAMD))

	default:
		wlog.Warn(fmt.Sprintf("call %s not have handler action %s", data.Id, data.Event))
	}
}
