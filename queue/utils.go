package queue

import (
	"encoding/json"
	"github.com/webitel/wlog"
)

func Assert(src interface{}) {
	if src == nil {
		panic("assert error")
	}
}

func DUMP(i interface{}) string {
	s, _ := json.MarshalIndent(i, "", "\t")
	wlog.Error(string(s))
	return string(s)
}
