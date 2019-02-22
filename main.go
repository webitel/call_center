package main

import (
	"fmt"
	"github.com/webitel/call_center/apis"
	"github.com/webitel/call_center/app"
	"github.com/webitel/call_center/mlog"

	"net/http"
	_ "net/http/pprof"
	"os"
	"os/signal"
	"syscall"
)

func main() {
	interruptChan := make(chan os.Signal, 1)
	a, err := app.New()
	if err != nil {
		panic(err.Error())
	}
	defer a.Shutdown()

	serverErr := a.StartServer()
	if serverErr != nil {
		mlog.Critical(serverErr.Error())
		return
	}
	apis.Init(a, a.Srv.Router)

	setDebug()
	// wait for kill signal before attempting to gracefully shutdown
	// the running service

	signal.Notify(interruptChan, os.Interrupt, syscall.SIGINT, syscall.SIGTERM)
	<-interruptChan
}

func setDebug() {
	//debug.SetGCPercent(-1)

	go func() {
		fmt.Println("Start debug server on :8090")
		fmt.Println("Debug: ", http.ListenAndServe(":8090", nil))
	}()

}
