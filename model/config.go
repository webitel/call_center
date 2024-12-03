package model

import "time"

const (
	DATABASE_DRIVER_POSTGRES = "postgres"
)

type ServiceSettings struct {
	NodeId *string `flag:"id|1|Service id" json:"id" env:"ID"`
	//ListenAddress         *string
	//ListenInternalAddress *string
}

type LogSettings struct {
	Lvl     string `json:"lvl" flag:"log_lvl|debug|Log level" env:"LOG_LVL"`
	Json    bool   `json:"json" flag:"log_json|false|Log format JSON" env:"LOG_JSON"`
	Otel    bool   `json:"otel" flag:"log_otel|false|Log OTEL" env:"LOG_OTEL"`
	File    string `json:"file" flag:"log_file||Log file directory" env:"LOG_FILE"`
	Console bool   `json:"console" flag:"log_console||Log console" env:"LOG_CONSOLE"`
}

type CallSettings struct {
	UseBridgeAnswerTimeout   bool   `json:"use_bridge_answer_timeout" flag:"use_bridge_answer_timeout|0|Bridge answer timeout" env:"USE_BRIDGE_ANSWER_TIMEOUT"`
	ResourceSipCidType       string `json:"resource_cid_type" flag:"resource_cid_type||CID Type: none / Remote-Party-ID / P-Asserted-Identity" env:"RESOURCE_CID_TYPE"`
	ResourceIgnoreEarlyMedia string `json:"resource_ignore_early_media" flag:"resource_ignore_early_media||Ignore Early Media: True / False / Consume / Ring Ready" env:"RESOURCE_IGNORE_EARLY_MEDIA"`
}

type SqlSettings struct {
	DriverName                  *string       `json:"driver_name" flag:"sql_driver_name|postgres|" env:"SQL_DRIVER_NAME"`
	DataSource                  *string       `json:"data_source" flag:"data_source|postgres://opensips:webitel@postgres:5432/webitel?fallback_application_name=engine&sslmode=disable&connect_timeout=10&search_path=call_center|Data source" env:"DATA_SOURCE"`
	DataSourceReplicas          []string      `json:"data_source_replicas" flag:"sql_data_source_replicas" default:"" env:"SQL_DATA_SOURCE_REPLICAS"`
	MaxIdleConns                *int          `json:"max_idle_conns" flag:"sql_max_idle_conns|5|Maximum idle connections" env:"SQL_MAX_IDLE_CONNS"`
	MaxOpenConns                *int          `json:"max_open_conns" flag:"sql_max_open_conns|5|Maximum open connections" env:"SQL_MAX_OPEN_CONNS"`
	ConnMaxLifetimeMilliseconds *int          `json:"conn_max_lifetime_milliseconds" flag:"sql_conn_max_lifetime_milliseconds|300000|Connection maximum lifetime milliseconds" env:"SQL_LIFETIME_MILLISECONDS"`
	Log                         bool          `json:"log" flag:"sql_log|false|Log SQL" env:"SQL_LOG"`
	LogMinDuration              time.Duration `json:"sql_log_min_duration" flag:"sql_log_min_duration|500ms|Log SQL" env:"SQL_LOG_MIN_DURATION"`
	QueryTimeout                *int          `json:"query_timeout" flag:"sql_query_timeout|10|Sql query timeout seconds" env:"QUERY_TIMEOUT"`
}

type MessageQueueSettings struct {
	Url string `flag:"amqp|amqp://webitel:webitel@rabbit:5672?heartbeat=10|AMQP connection" env:"AMQP"`
}

type ServerSettings struct {
	Address string `json:"address" flag:"grpc_addr||GRPC host" env:"GRPC_ADDR"`
	Port    int    `json:"port" flag:"grpc_port|0|GRPC port" env:"GRPC_PORT"`
	Network string `json:"network" flag:"grpc_network|tcp|GRPC network" env:"GRPC_NETWORK"`
}

type DiscoverySettings struct {
	Url string `json:"url" flag:"consul|172.0.0.1:8500|Host to consul" env:"CONSUL"`
}

type QueueSettings struct {
	WaitChannelClose  bool          `json:"wait_channel_close" flag:"wait_channel_close|0|Wait channel close" env:"WAIT_CHANNEL_CLOSE"`
	EnableOmnichannel bool          `json:"enable_omnichannel" flag:"enable_omnichannel|0|Set enabled omnichannel" env:"ENABLE_OMNICHANNEL"`
	BridgeSleep       time.Duration `json:"before_bridge_sleep" flag:"before_bridge_sleep|200ms|Before bridge sleep time" env:"BEFORE_BRIDGE_SLEEP"`
	PollingInterval   time.Duration `json:"polling_interval" flag:"polling_interval|500ms|Polling distribute interval (default 500ms)" env:"POLLING_INTERVAL"`
}

type Config struct {
	DiscoverySettings    DiscoverySettings    `json:"discovery_settings"`
	QueueSettings        QueueSettings        `json:"queue_settings"`
	ServiceSettings      ServiceSettings      `json:"service_settings"`
	ServerSettings       ServerSettings       `json:"server_settings"`
	SqlSettings          SqlSettings          `json:"sql_settings"`
	MessageQueueSettings MessageQueueSettings `json:"message_queue_settings"`
	CallSettings         CallSettings         `json:"call_settings"`
	Log                  LogSettings          `json:"log_settings"`
}
