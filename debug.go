package main

import (
	"fmt"
	"github.com/webitel/wlog"
	"net/http"
)

func setDev() {
	//debug.SetGCPercent(-1)

	go func() {
		wlog.Info(fmt.Sprintf("Start debug server on http://localhost:8090/debug/pprof/"))
		wlog.Info(fmt.Sprintf("Debug: %s", http.ListenAndServe(":8090", nil)))
	}()

}
