package model

import (
	"fmt"
	"strconv"
)

const (
	CallCenterExchange = "callcenter"

	QUEUE_MQ = "call-center-fs-events"

	MQ_EVENT_PREFIX             = "callcenter.event"
	MQ_QUEUE_COUNT_EVENT_PREFIX = "queue_count"
)

type Event map[string]interface{}

func (e Event) GetAttribute(name string) (interface{}, bool) {
	v, ok := e[name]
	return v, ok
}

func (e Event) Dump() {
	for k, v := range e {
		fmt.Println(fmt.Sprintf("%s - %v", k, v))
	}
}

func (e Event) GetIntAttribute(name string) (int, bool) {
	v, ok := e.GetAttribute(name)

	if !ok {
		return 0, false
	}

	switch v.(type) {
	case string:
		i, _ := strconv.Atoi(fmt.Sprintf("%s", v))
		return i, true
	default:
		//TODO
		return 0, false
	}
}

func (e Event) GetStrAttribute(name string) (string, bool) {
	v, ok := e.GetAttribute(name)

	if !ok {
		return "", false
	}

	return fmt.Sprintf("%v", v), true
}
