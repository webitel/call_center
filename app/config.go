package app

import (
	"flag"
	"fmt"
	"github.com/webitel/call_center/model"
	"time"
)

var (
	appId                    = flag.String("id", "1", "Service id")
	consulHost               = flag.String("consul", "172.0.0.1:8500", "Host to consul")
	dataSource               = flag.String("data_source", "postgres://opensips:webitel@postgres:5432/webitel?fallback_application_name=call_center&sslmode=disable&connect_timeout=10&search_path=call_center", "Data source")
	amqpSource               = flag.String("amqp", "amqp://webitel:webitel@rabbit:5672?heartbeat=10", "AMQP connection")
	grpcServerPort           = flag.Int("grpc_port", 0, "GRPC port")
	grpcServerAddr           = flag.String("grpc_addr", "", "GRPC host")
	useBridgeAnswerTimeout   = flag.Bool("use_bridge_answer_timeout", false, "bridge_answer_timeout")
	waitChannelClose         = flag.Int("wait_channel_close", 0, "Wait channel close")
	resourceCidType          = flag.String("resource_cid_type", "", "CID Type: none / Remote-Party-ID / P-Asserted-Identity")
	resourceIgnoreEarlyMedia = flag.String("resource_ignore_early_media", "", "Ignore Early Media: True / False / Consume / Ring Ready")
	traceSqlQueryDuration    = flag.Int("sql_log_duration", 0, "Log query duration")
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
		QueueSettings: model.QueueSettings{
			WaitChannelClose: waitChannelClose != nil && *waitChannelClose > 0,
		},
		ServiceSettings: model.ServiceSettings{
			NodeId: model.NewString(fmt.Sprintf("%s-%s", model.ServiceName, *appId)),
		},
		DiscoverySettings: model.DiscoverySettings{
			Url: *consulHost,
		},
		CallSettings: model.CallSettings{
			UseBridgeAnswerTimeout:   *useBridgeAnswerTimeout,
			ResourceSipCidType:       *resourceCidType,
			ResourceIgnoreEarlyMedia: *resourceIgnoreEarlyMedia,
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
			LogDuration:                 time.Millisecond * time.Duration(*traceSqlQueryDuration),
		},
		MessageQueueSettings: model.MessageQueueSettings{
			Url: *amqpSource,
		},
	}
	return config, nil
}
