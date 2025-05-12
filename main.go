package main

import (
	"fmt"
	"github.com/webitel/call_center/app"
	"github.com/webitel/call_center/grpc_api"
	"math/rand"
	"time"

	"github.com/webitel/wlog"
	_ "net/http/pprof"
	"os"
	"os/signal"
	"syscall"
)

//go:generate go run github.com/bufbuild/buf/cmd/buf@latest generate --template buf.gen.engine.yaml
//go:generate go run github.com/bufbuild/buf/cmd/buf@latest generate --template buf.gen.fs.yaml
//go:generate go run github.com/bufbuild/buf/cmd/buf@latest generate --template buf.gen.yaml

func main() {
	interruptChan := make(chan os.Signal, 1)
	a, err := app.New()
	wlog.Info(fmt.Sprintf("server build version: %s", app.Version()))
	if err != nil {
		panic(err.Error())
	}
	defer a.Shutdown()

	if err = a.StartGrpcServer(); err != nil {
		panic(err.Error())
	}

	grpc_api.Init(a, a.GrpcServer.Server())

	if a.Config().Dev {
		setDev()
	}

	// wait for kill signal before attempting to gracefully shutdown
	// the running service

	signal.Notify(interruptChan, os.Interrupt, syscall.SIGINT, syscall.SIGTERM)
	<-interruptChan
}

func init() {
	rand.Seed(time.Now().UTC().UnixNano())
}
