package app

import (
	"flag"
	"fmt"
	"github.com/webitel/call_center/model"
)

var (
	appId                 = flag.String("app_id", "1", "Service id")
	translationsDirectory = flag.String("translations_directory", "i18n", "Translations directory")
	consulHost            = flag.String("consul", "172.0.0.1:8500", "Host to consul")
	dataSource            = flag.String("data_source", "postgres://opensips:webitel@postgres:5432/webitel?fallback_application_name=engine&sslmode=disable&connect_timeout=10&search_path=call_center", "Data source")
	amqpSource            = flag.String("amqp", "amqp://webitel:webitel@rabbit:5672?heartbeat=10", "AMQP connection")
	grpcServerPort        = flag.Int("grpc_port", 0, "GRPC port")
	grpcServerAddr        = flag.String("grpc_addr", "", "GRPC host")
)

func (a *App) Config() *model.Config {
	if cfg := a.config.Load(); cfg != nil {
		return cfg.(*model.Config)
	}
	return &model.Config{}
}

func (a *App) LoadConfig(string) error {
	if conf, err := loadConfig(); err != nil {
		return err
	} else {
		a.config.Store(conf)
	}
	return nil
}

func loadConfig() (*model.Config, error) {
	flag.Parse()
	config := &model.Config{
		ServiceSettings: model.ServiceSettings{
			NodeId: model.NewString(fmt.Sprintf("%s-%s", model.ServiceName, *appId)),
		},
		DiscoverySettings: model.DiscoverySettings{
			Url: *consulHost,
		},
		ServerSettings: model.ServerSettings{
			Address: *grpcServerAddr,
			Port:    *grpcServerPort,
			Network: "tcp",
		},
		SqlSettings: model.SqlSettings{
			DriverName:                  model.NewString("postgres"),
			DataSource:                  dataSource,
			MaxIdleConns:                model.NewInt(5),
			MaxOpenConns:                model.NewInt(5),
			ConnMaxLifetimeMilliseconds: model.NewInt(300000),
			Trace:                       false,
		},
		MessageQueueSettings: model.MessageQueueSettings{
			Url: *amqpSource,
		},
	}
	return config, nil
}
