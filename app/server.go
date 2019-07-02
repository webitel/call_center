package app

import (
	"fmt"
	"github.com/gorilla/handlers"
	"github.com/gorilla/mux"
	"github.com/pkg/errors"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"net"
	"net/http"
	"strings"
	"time"
)

type Server struct {

	// RootRouter is the starting point for all HTTP requests to the server.
	RootRouter *mux.Router

	// Router is the starting point for all web, api4 and ws requests to the server. It differs
	// from RootRouter only if the SiteURL contains a /subpath.
	Router *mux.Router
	Store  store.Store

	Server     *http.Server
	ListenAddr *net.TCPAddr

	didFinishListen chan struct{}
}

type RecoveryLogger struct {
}

type CorsWrapper struct {
	router *mux.Router
}

func (cw *CorsWrapper) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	//TODO
	if r.Header.Get("Origin") == "" {
		w.Header().Set("Access-Control-Allow-Origin", "*")
	} else {
		w.Header().Set("Access-Control-Allow-Origin", r.Header.Get("Origin"))
	}

	if r.Method == "OPTIONS" {
		w.Header().Set(
			"Access-Control-Allow-Methods",
			strings.Join([]string{"GET", "POST", "PUT", "DELETE"}, ", "))

		w.Header().Set(
			"Access-Control-Allow-Headers",
			r.Header.Get("Access-Control-Request-Headers"))
	}

	if r.Method == "OPTIONS" {
		return
	}

	cw.router.ServeHTTP(w, r)
}

func (rl *RecoveryLogger) Println(i ...interface{}) {
	wlog.Error("Please check the std error output for the stack trace")
	wlog.Error(fmt.Sprint(i))
}

func (a *App) StartServer() error {
	wlog.Info("Starting Server...")

	var handler http.Handler = &CorsWrapper{a.Srv.RootRouter}

	a.Srv.Server = &http.Server{
		Handler:  handlers.RecoveryHandler(handlers.RecoveryLogger(&RecoveryLogger{}), handlers.PrintRecoveryStack(true))(handler),
		ErrorLog: a.Log.StdLog(wlog.String("source", "httpserver")),
	}

	addr := *a.Config().ServiceSettings.ListenAddress
	listener, err := net.Listen("tcp", addr)
	if err != nil {
		errors.Wrapf(err, utils.T("api.server.start_server.starting.critical"), err)
		return err
	}

	a.Srv.ListenAddr = listener.Addr().(*net.TCPAddr)
	wlog.Info(fmt.Sprintf("Server is listening on %v", listener.Addr().String()))
	a.Srv.didFinishListen = make(chan struct{})

	go func() {
		var err error

		err = a.Srv.Server.Serve(listener)
		if err != nil && err != http.ErrServerClosed {
			wlog.Critical(fmt.Sprintf("Error starting server, err:%v", err))
			time.Sleep(time.Second)
		}
		close(a.Srv.didFinishListen)
	}()

	return nil
}
