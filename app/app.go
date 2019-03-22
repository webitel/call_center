package app

import (
	"fmt"
	"github.com/gorilla/mux"
	"github.com/pkg/errors"
	"github.com/webitel/call_center/engine"
	"github.com/webitel/call_center/externalCommands"
	"github.com/webitel/call_center/externalCommands/grpc"
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
	"github.com/webitel/call_center/mq/rabbit"
	"github.com/webitel/call_center/queue"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/store/sqlstore"
	"github.com/webitel/call_center/utils"
	"net/http"
	"sync/atomic"
)

type App struct {
	id               *string
	Srv              *Server
	Store            store.Store
	MQ               mq.MQ
	ExternalCommands externalCommands.Commands
	Log              *mlog.Logger
	configFile       string
	config           atomic.Value
	sessionCache     *utils.Cache
	newStore         func() store.Store
	engine           engine.Engine
	dialing          queue.Dialing
}

func New(options ...string) (outApp *App, outErr error) {
	rootRouter := mux.NewRouter()

	app := &App{
		id: model.NewString("node-1"),
		Srv: &Server{
			RootRouter: rootRouter,
		},
		sessionCache: utils.NewLru(model.SESSION_CACHE_SIZE),
	}
	app.Srv.Router = app.Srv.RootRouter.PathPrefix("/").Subrouter()

	defer func() {
		if outErr != nil {
			app.Shutdown()
		}
	}()

	if utils.T == nil {
		if err := utils.TranslationsPreInit(); err != nil {
			return nil, errors.Wrapf(err, "unable to load Mattermost translation files")
		}
	}

	model.AppErrorInit(utils.T)

	if err := app.LoadConfig(app.configFile); err != nil {
		return nil, err
	}
	app.Log = mlog.NewLogger(&mlog.LoggerConfiguration{
		EnableConsole: true,
		ConsoleLevel:  mlog.LevelDebug,
	})

	mlog.RedirectStdLog(app.Log)
	mlog.InitGlobalLogger(app.Log)

	if err := utils.InitTranslations(app.Config().LocalizationSettings); err != nil {
		return nil, errors.Wrapf(err, "unable to load translation files")
	}

	mlog.Info("Server is initializing...")

	if app.newStore == nil {
		app.newStore = func() store.Store {
			return store.NewLayeredStore(sqlstore.NewSqlSupplier(app.Config().SqlSettings))
		}
	}

	app.Srv.Store = app.newStore()
	app.Store = app.Srv.Store
	app.MQ = mq.NewMQ(rabbit.NewRabbitMQ(app.Config().MQSettings, app.GetInstanceId()))

	app.ExternalCommands = grpc.NewCommands(app.Config().ExternalCommandsSettings)

	app.Srv.Router.NotFoundHandler = http.HandlerFunc(app.Handle404)

	app.engine = engine.NewEngine(*app.id, app.Store)
	app.engine.Start()

	app.dialing = queue.NewDialing(app, app.Store)
	app.dialing.Start()

	return app, outErr
}

func (app *App) IsReady() bool {
	//TODO check connect to db, rabbit, grpc
	return true
}

func (app *App) Shutdown() {
	mlog.Info("Stopping Server...")
	app.engine.Stop()
	app.dialing.Stop()
	app.MQ.Close()
	app.ExternalCommands.Close()
}

func (a *App) Handle404(w http.ResponseWriter, r *http.Request) {
	err := model.NewAppError("Handle404", "api.context.404.app_error", nil, r.URL.String(), http.StatusNotFound)
	mlog.Debug(fmt.Sprintf("%v: code=404 ip=%v", r.URL.Path, utils.GetIpAddress(r)))
	utils.RenderWebAppError(a.Config(), w, r, err)
}

func (a *App) GetInstanceId() string {
	return *a.id
}
