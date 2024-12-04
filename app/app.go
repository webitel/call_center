package app

import (
	"context"
	"fmt"
	"github.com/pkg/errors"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/chat"
	"github.com/webitel/call_center/cluster"
	"github.com/webitel/call_center/engine"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
	"github.com/webitel/call_center/mq/rabbit"
	"github.com/webitel/call_center/queue"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/store/sqlstore"
	"github.com/webitel/call_center/trigger"
	"github.com/webitel/flow_manager/client"
	"github.com/webitel/wlog"
	"sync/atomic"

	otelsdk "github.com/webitel/webitel-go-kit/otel/sdk"
	"go.opentelemetry.io/otel/sdk/resource"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"

	// -------------------- plugin(s) -------------------- //
	_ "github.com/webitel/webitel-go-kit/otel/sdk/log/otlp"
	_ "github.com/webitel/webitel-go-kit/otel/sdk/log/stdout"
	_ "github.com/webitel/webitel-go-kit/otel/sdk/metric/otlp"
	_ "github.com/webitel/webitel-go-kit/otel/sdk/metric/stdout"
	_ "github.com/webitel/webitel-go-kit/otel/sdk/trace/otlp"
	_ "github.com/webitel/webitel-go-kit/otel/sdk/trace/stdout"
)

type App struct {
	id             *string
	publicId       string
	Store          store.Store
	MQ             mq.MQ
	Log            *wlog.Logger
	configFile     string
	config         atomic.Value
	newStore       func() store.Store
	cluster        cluster.Cluster
	engine         engine.Engine
	dialing        queue.Dialing
	GrpcServer     *GrpcServer
	agentManager   agent_manager.AgentManager
	callManager    call_manager.CallManager
	flowManager    client.FlowManager
	chatManager    *chat.ChatManager
	triggerManager *trigger.Manager

	ctx              context.Context
	otelShutdownFunc otelsdk.ShutdownFunc
}

func New(options ...string) (outApp *App, outErr error) {
	app := &App{
		ctx: context.Background(),
	}

	defer func() {
		if outErr != nil {
			app.Shutdown()
		}
	}()

	if err := app.LoadConfig(app.configFile); err != nil {
		return nil, err
	}
	config := app.Config()
	// TODO
	app.setServiceId(app.Config().ServiceSettings.NodeId)

	logConfig := &wlog.LoggerConfiguration{
		EnableConsole: config.Log.Console,
		ConsoleJson:   false,
		ConsoleLevel:  config.Log.Lvl,
	}

	if config.Log.File != "" {
		logConfig.FileLocation = config.Log.File
		logConfig.EnableFile = true
		logConfig.FileJson = true
		logConfig.FileLevel = config.Log.Lvl
	}

	if config.Log.Otel {
		// TODO
		var err error
		logConfig.EnableExport = true
		app.otelShutdownFunc, err = otelsdk.Configure(
			app.ctx,
			otelsdk.WithResource(resource.NewSchemaless(
				semconv.ServiceName(model.ServiceName),
				semconv.ServiceVersion(model.CurrentVersion),
				semconv.ServiceInstanceID(*app.id),
				semconv.ServiceNamespace("webitel"),
			)),
		)
		if err != nil {
			return nil, err
		}
	}
	app.Log = wlog.NewLogger(logConfig)

	wlog.RedirectStdLog(app.Log)
	wlog.InitGlobalLogger(app.Log)

	app.Log.Info("server is initializing...")

	if app.newStore == nil {
		app.newStore = func() store.Store {
			return store.NewLayeredStore(sqlstore.NewSqlSupplier(app.Config().SqlSettings))
		}
	}

	app.Store = app.newStore()
	app.MQ = mq.NewMQ(rabbit.NewRabbitMQ(app.Config().MessageQueueSettings, app.GetInstanceId(), app.Log))

	if cl, err := cluster.NewCluster(*app.id, app.Config().DiscoverySettings.Url, app.Store.Cluster(), app.Log); err != nil {
		return nil, err
	} else {
		app.cluster = cl
	}

	app.GrpcServer = NewGrpcServer(app.Config().ServerSettings, app.Log)

	if err := app.cluster.Setup(); err != nil {
		return nil, errors.Wrapf(err, "unable to initialize cluster")
	}

	if err := app.cluster.Start(app.GrpcServer.GetPublicInterface()); err != nil {
		return nil, err
	}

	app.callManager = call_manager.NewCallManager(app.GetInstanceId(), app.Cluster().ServiceDiscovery(), app.MQ, app.Log)
	app.callManager.Start()

	app.engine = engine.NewEngine(app, *app.id, app.Store, app.Config().QueueSettings.EnableOmnichannel,
		app.Config().QueueSettings.PollingInterval, app.Log)
	app.engine.Start()

	app.agentManager = agent_manager.NewAgentManager(app.GetInstanceId(), app.Store, app.MQ, app.Log)
	app.agentManager.SetHookAutoOfflineAgent(app.hookAutoOfflineAgent)
	app.agentManager.Start()

	app.flowManager = client.NewFlowManager(app.Cluster().ServiceDiscovery())
	if err := app.flowManager.Start(); err != nil {
		return nil, err
	}

	app.chatManager = chat.NewChatManager(app.Cluster().ServiceDiscovery(), app.MQ, app.Log)
	if err := app.chatManager.Start(); err != nil {
		return nil, err
	}

	app.dialing = queue.NewDialing(app, app.MQ, app.callManager, app.agentManager, app.Store, app.Config().QueueSettings.BridgeSleep)
	app.dialing.Start()

	app.triggerManager = trigger.NewManager(*app.id, app.Store, app.flowManager, app.Log)
	if err := app.triggerManager.Start(); err != nil {
		return nil, err
	}

	return app, outErr
}

func (app *App) IsReady() bool {
	//TODO check connect to db, rabbit, grpc
	return app.callManager.CountConnection() > 0
}

func (app *App) FlowManager() client.FlowManager {
	return app.flowManager
}

func (app *App) Queue() queue.Dialing {
	return app.dialing
}

func (app *App) Master() bool {
	return app.cluster.Master()
}

func (app *App) QueueSettings() model.QueueSettings {
	return app.Config().QueueSettings
}

func (app *App) Shutdown() {
	app.Log.Info("stopping Server...")

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

	if app.flowManager != nil {
		app.flowManager.Stop()
	}

	if app.chatManager != nil {
		app.chatManager.Stop()
	}

	if app.triggerManager != nil {
		app.triggerManager.Stop()
	}

	if app.MQ != nil {
		app.MQ.Close()
	}

	if app.otelShutdownFunc != nil {
		app.otelShutdownFunc(app.ctx)
	}
}

func (a *App) setServiceId(id *string) {
	a.id = id
	a.publicId = fmt.Sprintf("%s-%s", model.ServiceName, *a.id)
}

func (a *App) GetInstanceId() string {
	return a.publicId
}
