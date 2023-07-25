module github.com/webitel/call_center

go 1.18

require (
	github.com/go-gorp/gorp v2.2.0+incompatible
	github.com/lib/pq v1.10.7
	github.com/olebedev/emitter v0.0.0-20190110104742-e8d1457e6aee
	github.com/pborman/uuid v1.2.1
	github.com/pkg/errors v0.9.1
	github.com/streadway/amqp v1.0.0
	github.com/webitel/engine v0.0.0-20230524103526-5ba03e19f192
	github.com/webitel/flow_manager v0.0.0-20230414112735-d8214c2ef295
	github.com/webitel/protos/cc v0.0.0-20230623094357-9bf3eb56875a
	github.com/webitel/protos/fs v0.0.0-20230202145403-c92fa287810a
	github.com/webitel/protos/workflow v0.0.0-20230413090020-f5f4e9d27dc4
	github.com/webitel/wlog v0.0.0-20220608103744-93b33e61bd28
	golang.org/x/sync v0.1.0
	golang.org/x/time v0.0.0-20220411224347-583f2d630306
	google.golang.org/grpc v1.54.0
)

require (
	github.com/armon/go-metrics v0.4.1 // indirect
	github.com/fatih/color v1.14.1 // indirect
	github.com/go-sql-driver/mysql v1.7.0 // indirect
	github.com/golang/protobuf v1.5.3 // indirect
	github.com/google/btree v1.0.0 // indirect
	github.com/google/uuid v1.3.0 // indirect
	github.com/grpc-ecosystem/grpc-gateway v1.16.0 // indirect
	github.com/hashicorp/consul/api v1.19.1 // indirect
	github.com/hashicorp/go-cleanhttp v0.5.2 // indirect
	github.com/hashicorp/go-hclog v1.4.0 // indirect
	github.com/hashicorp/go-immutable-radix v1.3.1 // indirect
	github.com/hashicorp/go-rootcerts v1.0.2 // indirect
	github.com/hashicorp/golang-lru v0.5.4 // indirect
	github.com/hashicorp/serf v0.10.1 // indirect
	github.com/mattn/go-colorable v0.1.13 // indirect
	github.com/mattn/go-isatty v0.0.17 // indirect
	github.com/mattn/go-sqlite3 v1.14.6 // indirect
	github.com/mitchellh/go-homedir v1.1.0 // indirect
	github.com/mitchellh/mapstructure v1.5.0 // indirect
	github.com/nicksnyder/go-i18n v1.10.1 // indirect
	github.com/pelletier/go-toml v1.9.5 // indirect
	github.com/stretchr/testify v1.8.1 // indirect
	github.com/webitel/protos/engine v0.0.0-20230524090136-727f562cdf9c // indirect
	go.uber.org/atomic v1.10.0 // indirect
	go.uber.org/multierr v1.9.0 // indirect
	go.uber.org/zap v1.24.0 // indirect
	golang.org/x/net v0.9.0 // indirect
	golang.org/x/oauth2 v0.5.0 // indirect
	golang.org/x/sys v0.7.0 // indirect
	golang.org/x/text v0.9.0 // indirect
	google.golang.org/appengine v1.6.7 // indirect
	google.golang.org/genproto v0.0.0-20230410155749-daa745c078e1 // indirect
	google.golang.org/protobuf v1.30.0 // indirect
	gopkg.in/natefinch/lumberjack.v2 v2.2.1 // indirect
	gopkg.in/yaml.v2 v2.4.0 // indirect
)

replace (
	github.com/webitel/protos/cc => ../protos/cc
)