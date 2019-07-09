package call_manager

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
	"github.com/webitel/wlog"
)

func (cm *CallManagerImpl) handleCallEvent(event mq.Event) {
	var linkId string
	var ok bool
	var call Call

	if linkId, ok = event.GetVariable(model.CALL_ID); !ok {
		//
		wlog.Debug(fmt.Sprintf("skip event %s [%s - %s]", event.Name(), event.NodeName(), event.Id()))
		return
	}

	if call, ok = cm.GetCall(linkId); !ok {
		//
		wlog.Debug(fmt.Sprintf("skip event %s [%s - %s]", event.Name(), event.NodeName(), event.Id()))
		return
	}

	switch event.Name() {
	case model.CALL_EVENT_HANGUP:
		if _, ok = event.GetVariable("grpc_originate_success"); !ok {
			wlog.Debug(fmt.Sprintf("skip event %s [%s - %s]", event.Name(), event.NodeName(), event.Id()))
			return
		}
		call.SetHangupCall(event)
		cm.RemoveCall(linkId)
	case model.CALL_EVENT_BRIDGE:
		call.(*CallImpl).setState(CALL_STATE_BRIDGE)
	case model.CALL_EVENT_PARK:
		//TODO
		call.(*CallImpl).setState(CALL_STATE_PARK)
	}
}
