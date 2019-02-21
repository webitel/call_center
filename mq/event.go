package mq

import "fmt"

type Event map[string]interface{}

func (e Event) Name() string {
	if v, ok := e["Event-Name"]; ok {
		return fmt.Sprintf("%v", v)
	}
	return ""
}
