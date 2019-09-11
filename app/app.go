package app

import (
	"github.com/pkg/errors"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/cluster"
	"github.com/webitel/call_center/engine"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
	"github.com/webitel/call_center/mq/rabbit"
	"github.com/webitel/call_center/queue"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/store/sqlstore"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"sync/atomic"
)

type App struct {
	id           *string
	Store        store.Store
	MQ           mq.MQ
	Log          *wlog.Logger
	configFile   string
	config       atomic.Value
	newStore     func() store.Store
	cluster      cluster.Cluster
	engine       engine.Engine
	dialing      queue.Dialing
	agentManager agent_manager.AgentManager
	callManager  call_manager.CallManager
}

func New(options ...string) (outApp *App, outErr error) {
	var err *model.AppError

	app := &App{}

	defer func() {
		if outErr != nil {
			app.Shutdown()
		}
	}()

	if utils.T == nil {
		if err := utils.TranslationsPreInit(); err != nil {
			return nil, errors.Wrapf(err, "unable to load translation files")
		}
	}

	model.AppErrorInit(utils.T)

	if err = app.LoadConfig(app.configFile); err != nil {
		return nil, err
	}
	app.id = app.Config().ServiceSettings.NodeId
	app.Log = wlog.NewLogger(&wlog.LoggerConfiguration{
		EnableConsole: true,
		ConsoleLevel:  wlog.LevelDebug,
	})

	wlog.RedirectStdLog(app.Log)
	wlog.InitGlobalLogger(app.Log)

	if err := utils.InitTranslations(app.Config().LocalizationSettings); err != nil {
		return nil, errors.Wrapf(err, "unable to load translation files")
	}

	wlog.Info("server is initializing...")

	if app.newStore == nil {
		app.newStore = func() store.Store {
			return store.NewLayeredStore(sqlstore.NewSqlSupplier(app.Config().SqlSettings))
		}
	}

	app.Store = app.newStore()
	app.MQ = mq.NewMQ(rabbit.NewRabbitMQ(app.Config().MQSettings, app.GetInstanceId()))

	if cluster, err := cluster.NewCluster(*app.id, "192.168.177.199:8500", app.Store.Cluster()); err != nil {
		return nil, err
	} else {
		app.cluster = cluster
	}

	if err := app.cluster.Setup(); err != nil {
		return nil, errors.Wrapf(err, "unable to initialize cluster")
	}
	app.cluster.Start()

	app.callManager = call_manager.NewCallManager(app.GetInstanceId(), app.Cluster().ServiceDiscovery(), app.MQ)
	app.callManager.Start()

	app.engine = engine.NewEngine(*app.id, app.Store)
	app.engine.Start()

	app.agentManager = agent_manager.NewAgentManager(app.GetInstanceId(), app.Store)
	app.agentManager.Start()

	app.dialing = queue.NewDialing(app, app.callManager, app.agentManager, app.Store)
	app.dialing.Start()

	return app, outErr
}

func (app *App) IsReady() bool {
	//TODO check connect to db, rabbit, grpc
	return true
}

func (app *App) Shutdown() {
	wlog.Info("stopping Server...")

	if app.cluster != nil {
		app.cluster.Stop()
	}

	if app.engine != nil {
		app.engine.Stop()
	}

	if app.dialing != nil {
		app.dialing.Stop()
	}

	if app.agentManager != nil {
		app.agentManager.Stop()
	}

	if app.callManager != nil {
		app.callManager.Stop()
	}

	app.MQ.Close()
}

func (a *App) GetInstanceId() string {
	return *a.id
}
