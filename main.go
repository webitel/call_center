package main

import (
	"fmt"
	"github.com/webitel/call_center/apis"
	"github.com/webitel/call_center/app"

	"github.com/webitel/wlog"
	"math/rand"
	"net/http"
	_ "net/http/pprof"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func init() {
	rand.Seed(time.Now().UTC().UnixNano())
}

func main() {
	interruptChan := make(chan os.Signal, 1)
	a, err := app.New()
	if err != nil {
		panic(err.Error())
	}
	defer a.Shutdown()

	serverErr := a.StartServer()
	if serverErr != nil {
		wlog.Critical(serverErr.Error())
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
		wlog.Info(fmt.Sprintf("Start debug server on http://localhost:8090/debug/pprof/"))
		wlog.Info(fmt.Sprintf("Debug: ", http.ListenAndServe(":8090", nil)))
	}()

}
