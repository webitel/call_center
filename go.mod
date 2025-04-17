module github.com/webitel/call_center

go 1.22.5
toolchain go1.24.1

require (
	buf.build/gen/go/webitel/cc/grpc/go v1.5.1-20250414063239-00fc6a2d0c7b.2
	buf.build/gen/go/webitel/cc/protocolbuffers/go v1.36.6-20250414063239-00fc6a2d0c7b.1
	buf.build/gen/go/webitel/fs/grpc/go v1.3.0-20240425073915-5e104cd55a71.2
	buf.build/gen/go/webitel/fs/protocolbuffers/go v1.33.0-20240425073915-5e104cd55a71.1
	buf.build/gen/go/webitel/workflow/protocolbuffers/go v1.36.6-20250414063240-06c5c0a2dc53.1
	github.com/BoRuDar/configuration/v4 v4.5.0
	github.com/go-gorp/gorp v2.2.0+incompatible
	github.com/lib/pq v1.10.9
	github.com/olebedev/emitter v0.0.0-20190110104742-e8d1457e6aee
	github.com/pborman/uuid v1.2.1
	github.com/pkg/errors v0.9.1
	github.com/streadway/amqp v1.1.0
	github.com/webitel/engine v0.0.0-20250218105549-555f71cb7b0f
	github.com/webitel/flow_manager v0.0.0-20250414100900-060e49200e72
	github.com/webitel/webitel-go-kit v0.0.13-0.20240908192731-3abe573c0e41
	github.com/webitel/wlog v0.0.0-20240909100805-822697e17a45
	go.opentelemetry.io/otel v1.29.0
	go.opentelemetry.io/otel/sdk v1.29.0
	golang.org/x/sync v0.12.0
	golang.org/x/time v0.5.0
	google.golang.org/grpc v1.65.0
)

require (
	buf.build/gen/go/grpc-ecosystem/grpc-gateway/protocolbuffers/go v1.36.6-20241220201140-4c5ba75caaf8.1 // indirect
	buf.build/gen/go/webitel/chat/grpc/go v1.5.1-20250408125457-371160df8edc.2 // indirect
	buf.build/gen/go/webitel/chat/protocolbuffers/go v1.36.6-20250408125457-371160df8edc.1 // indirect
	buf.build/gen/go/webitel/engine/protocolbuffers/go v1.36.6-20250408125948-099378df4bdb.1 // indirect
	buf.build/gen/go/webitel/webitel-go/grpc/go v1.5.1-20250218105124-2ee3869e4b3a.2 // indirect
	buf.build/gen/go/webitel/webitel-go/protocolbuffers/go v1.36.5-20250218105124-2ee3869e4b3a.1 // indirect
	buf.build/gen/go/webitel/workflow/grpc/go v1.5.1-20250414063240-06c5c0a2dc53.2 // indirect
	github.com/armon/go-metrics v0.4.1 // indirect
	github.com/cenkalti/backoff/v4 v4.3.0 // indirect
	github.com/fatih/color v1.16.0 // indirect
	github.com/go-logr/logr v1.4.2 // indirect
	github.com/go-logr/stdr v1.2.2 // indirect
	github.com/google/uuid v1.6.0 // indirect
	github.com/grpc-ecosystem/grpc-gateway/v2 v2.21.0 // indirect
	github.com/hashicorp/consul/api v1.28.2 // indirect
	github.com/hashicorp/errwrap v1.1.0 // indirect
	github.com/hashicorp/go-cleanhttp v0.5.2 // indirect
	github.com/hashicorp/go-hclog v1.6.3 // indirect
	github.com/hashicorp/go-immutable-radix v1.3.1 // indirect
	github.com/hashicorp/go-multierror v1.1.1 // indirect
	github.com/hashicorp/go-rootcerts v1.0.2 // indirect
	github.com/hashicorp/go-version v1.6.0 // indirect
	github.com/hashicorp/golang-lru v1.0.2 // indirect
	github.com/hashicorp/serf v0.10.1 // indirect
	github.com/mattn/go-colorable v0.1.13 // indirect
	github.com/mattn/go-isatty v0.0.20 // indirect
	github.com/mitchellh/go-homedir v1.1.0 // indirect
	github.com/mitchellh/mapstructure v1.5.0 // indirect
	github.com/nicksnyder/go-i18n v1.10.1 // indirect
	github.com/pelletier/go-toml v1.9.5 // indirect
	go.opentelemetry.io/contrib/bridges/otelzap v0.0.0-20240812153829-bb9ac54eca05 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploggrpc v0.0.0-20240805233418-127d068751eb // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploghttp v0.4.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc v1.28.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp v1.28.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlptrace v1.28.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc v1.28.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp v1.28.0 // indirect
	go.opentelemetry.io/otel/exporters/stdout/stdoutmetric v1.28.0 // indirect
	go.opentelemetry.io/otel/exporters/stdout/stdouttrace v1.28.0 // indirect
	go.opentelemetry.io/otel/log v0.5.0 // indirect
	go.opentelemetry.io/otel/metric v1.29.0 // indirect
	go.opentelemetry.io/otel/sdk/log v0.5.0 // indirect
	go.opentelemetry.io/otel/sdk/metric v1.28.0 // indirect
	go.opentelemetry.io/otel/trace v1.29.0 // indirect
	go.opentelemetry.io/proto/otlp v1.3.1 // indirect
	go.uber.org/atomic v1.11.0 // indirect
	go.uber.org/multierr v1.11.0 // indirect
	go.uber.org/zap v1.27.0 // indirect
	golang.org/x/exp v0.0.0-20240404231335-c0f41cb1a7a0 // indirect
	golang.org/x/net v0.38.0 // indirect
	golang.org/x/oauth2 v0.21.0 // indirect
	golang.org/x/sys v0.31.0 // indirect
	golang.org/x/text v0.23.0 // indirect
	google.golang.org/genproto/googleapis/api v0.0.0-20240805194559-2c9e96a0b5d4 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20240805194559-2c9e96a0b5d4 // indirect
	google.golang.org/protobuf v1.36.6 // indirect
	gopkg.in/natefinch/lumberjack.v2 v2.2.1 // indirect
	gopkg.in/yaml.v2 v2.4.0 // indirect
)
