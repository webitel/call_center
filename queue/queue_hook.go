package queue

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/protos/workflow"
)

const (
	HookJoined   = "joined"
	HookAnswered = "answered"
	HookOffering = "offering"
	HookBridged  = "bridged"
	HookMissed   = "missed"
	HookLeaving  = "leaving"
)

/*
	reporting cause

*/

type hook struct {
	//Properties []string `json:"properties"`
	SchemaId uint32 `json:"schema_id"`
}

type HookHub struct {
	events map[string]hook
	len    uint
}

func NewHookHub(s []*model.QueueHook) HookHub {
	var h HookHub
	h.events = make(map[string]hook)

	for _, v := range s {
		// todo validate
		h.events[v.Event] = hook{
			//Properties: v.Properties,
			SchemaId: v.SchemaId,
		}
		h.len++
	}

	return h
}

func (hb *HookHub) getByName(name string) (hook, bool) {
	if hb.len == 0 {

		return hook{}, false
	}

	h, ok := hb.events[name]
	return h, ok
}

func (q *BaseQueue) Hook(name string, at *Attempt) {
	h, ok := q.hooks.getByName(name)
	if !ok {

		return
	}

	// add params last attempt
	req := &workflow.StartFlowRequest{
		SchemaId: h.SchemaId,
		DomainId: q.DomainId(),
		Variables: model.UnionStringMaps(
			at.ExportSchemaVariables(),
			q.variables,
			map[string]string{
				"state":   at.GetState(),
				"channel": q.channel,
			},
		),
	}

	id, err := q.queueManager.app.FlowManager().Queue().StartFlow(req)

	//call_manager.DUMP(req.Variables)

	if err != nil {
		at.Log(fmt.Sprintf("hook \"%s\", error: %s", name, err.Error()))
	} else {
		at.Log(fmt.Sprintf("hook \"%s\" external job_id: %s", name, id))
	}
}
