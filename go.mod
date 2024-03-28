module github.com/webitel/call_center

go 1.19

require (
	github.com/go-gorp/gorp v2.2.0+incompatible
	github.com/lib/pq v1.10.9
	github.com/olebedev/emitter v0.0.0-20190110104742-e8d1457e6aee
	github.com/pborman/uuid v1.2.1
	github.com/pkg/errors v0.9.1
	github.com/streadway/amqp v1.1.0
	github.com/webitel/engine v0.0.0-20240327135406-7469d4bcb04b
	github.com/webitel/flow_manager v0.0.0-20240318151852-e35870a75700
	github.com/webitel/protos/cc v0.0.0-20240328112808-7000c2969bbe
	github.com/webitel/protos/fs v0.0.0-20240327130525-7501c51c7a8e
	github.com/webitel/protos/workflow v0.0.0-20240327132302-ffcc68b6314f
	github.com/webitel/wlog v0.0.0-20220608103744-93b33e61bd28
	golang.org/x/sync v0.4.0
	golang.org/x/time v0.0.0-20220411224347-583f2d630306
	google.golang.org/grpc v1.58.3
)

require (
	github.com/armon/go-metrics v0.4.1 // indirect
	github.com/fatih/color v1.15.0 // indirect
	github.com/golang/protobuf v1.5.3 // indirect
	github.com/google/uuid v1.3.1 // indirect
	github.com/grpc-ecosystem/grpc-gateway/v2 v2.18.0 // indirect
	github.com/hashicorp/consul/api v1.25.1 // indirect
	github.com/hashicorp/go-cleanhttp v0.5.2 // indirect
	github.com/hashicorp/go-hclog v1.5.0 // indirect
	github.com/hashicorp/go-immutable-radix v1.3.1 // indirect
	github.com/hashicorp/go-rootcerts v1.0.2 // indirect
	github.com/hashicorp/golang-lru v1.0.2 // indirect
	github.com/hashicorp/serf v0.10.1 // indirect
	github.com/mattn/go-colorable v0.1.13 // indirect
	github.com/mattn/go-isatty v0.0.19 // indirect
	github.com/mitchellh/go-homedir v1.1.0 // indirect
	github.com/mitchellh/mapstructure v1.5.0 // indirect
	github.com/nicksnyder/go-i18n v1.10.1 // indirect
	github.com/pelletier/go-toml v1.9.5 // indirect
	github.com/rogpeppe/go-internal v1.11.0 // indirect
	github.com/webitel/protos/engine v0.0.0-20240327132302-ffcc68b6314f // indirect
	go.uber.org/atomic v1.11.0 // indirect
	go.uber.org/multierr v1.11.0 // indirect
	go.uber.org/zap v1.26.0 // indirect
	golang.org/x/exp v0.0.0-20231006140011-7918f672742d // indirect
	golang.org/x/net v0.17.0 // indirect
	golang.org/x/oauth2 v0.13.0 // indirect
	golang.org/x/sys v0.13.0 // indirect
	golang.org/x/text v0.14.0 // indirect
	google.golang.org/appengine v1.6.8 // indirect
	google.golang.org/genproto v0.0.0-20231012201019-e917dd12ba7a // indirect
	google.golang.org/genproto/googleapis/api v0.0.0-20231012201019-e917dd12ba7a // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20231012201019-e917dd12ba7a // indirect
	google.golang.org/protobuf v1.31.0 // indirect
	gopkg.in/natefinch/lumberjack.v2 v2.2.1 // indirect
	gopkg.in/yaml.v2 v2.4.0 // indirect
)

replace github.com/webitel/flow_manager => ../flow_manager
