package call_manager

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
)

type CallEvent struct {
	model.Event
}

func (e *CallEvent) GetVariable(name string) (string, bool) {
	return e.GetStrAttribute("variable_" + name)
}

func (e *CallEvent) NodeName() string {
	v, _ := e.GetStrAttribute("FreeSWITCH-Switchname")
	return v
}
func (e *CallEvent) Id() string {
	v, _ := e.GetStrAttribute("Unique-ID")
	return v
}

func (e *CallEvent) Name() string {
	v, _ := e.GetStrAttribute("Event-Name")
	return v
}

func (cm *CallManagerImpl) newInboundCall(fromNode string, event *CallEvent) *model.AppError {
	api, err := cm.pool.getByName(fromNode)

	if err != nil {
		return err
	}

	call := &CallImpl{
		id:        event.Id(),
		api:       api,
		cm:        cm,
		hangup:    make(chan struct{}),
		lastEvent: event,
	}

	call.setState(CALL_STATE_ACCEPT)
	cm.saveToCacheCall(call)

	cm.inboundCall <- call

	return nil
}

func (cm *CallManagerImpl) handleCallEvent(event model.Event) {
	var ok bool
	var name string

	callEvent := &CallEvent{event}

	name, ok = event.GetStrAttribute(model.CALL_ATTRIBUTE_EVENT_NAME)
	if !ok {

	}

	wlog.Debug(fmt.Sprintf("[%s] call %s receive event %s", callEvent.NodeName(), callEvent.Id(), name))

	if name == model.CALL_EVENT_CUSTOM {

		var action string
		action, ok = callEvent.GetStrAttribute("Action")

		switch action {
		case "hold":
			err := cm.newInboundCall(callEvent.NodeName(), callEvent)
			if err != nil {
				wlog.Error(fmt.Sprintf("[%s] call %s error: %s", callEvent.NodeName(), callEvent.Id(), err.Error()))
			}
		case "bridge":
			//TODO
		case "exit":
			if call, ok := cm.GetCall(callEvent.Id()); !ok {
				wlog.Debug(fmt.Sprintf("[%s] call %s skip event %s, not found in cache]", callEvent.NodeName(), callEvent.Id(), name))
				return
			} else {
				if _, ok = callEvent.GetStrAttribute("Other-Leg-Unique-ID"); ok {
					return
				}
				call.SetHangupCall(callEvent)
				cm.removeFromCacheCall(call)
			}

		default:
			wlog.Error(fmt.Sprintf("[%s] call %s skip inbound call event action: %s", callEvent.NodeName(), callEvent.Id(), action))
		}
	} else {
		cm.handleOutboundCalls(name, callEvent)
	}
}

func (cm *CallManagerImpl) handleOutboundCalls(eventName string, event *CallEvent) {
	var ok bool
	var call Call

	if call, ok = cm.GetCall(event.Id()); !ok {
		wlog.Debug(fmt.Sprintf("[%s] call %s skip event %s, not found in cache]", event.NodeName(), event.Id(), eventName))
		return
	}

	switch eventName {
	case model.CALL_EVENT_HANGUP:
		if _, ok = event.GetVariable("grpc_originate_success"); !ok {
			wlog.Debug(fmt.Sprintf("[%s] call %s skip event %s, bad originate]", event.NodeName(), event.Id(), eventName))
			return
		}
		call.SetHangupCall(event)
		cm.removeFromCacheCall(call)
	case model.CALL_EVENT_BRIDGE:
		call.(*CallImpl).setState(CALL_STATE_BRIDGE)
	case model.CALL_EVENT_PARK:
		//TODO
		call.(*CallImpl).setState(CALL_STATE_PARK)
	}
}
