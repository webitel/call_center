module github.com/webitel/call_center

go 1.18

require (
	github.com/go-gorp/gorp v2.2.0+incompatible
	github.com/golang/protobuf v1.5.2
	github.com/lib/pq v1.10.5
	github.com/olebedev/emitter v0.0.0-20190110104742-e8d1457e6aee
	github.com/pborman/uuid v1.2.1
	github.com/pkg/errors v0.9.1
	github.com/streadway/amqp v1.0.0
	github.com/webitel/engine v0.0.0-20220504115625-fd7060288b43
	github.com/webitel/flow_manager v0.0.0-20220504115825-744346294ebc
	github.com/webitel/protos/cc v0.0.0-20220504085106-475035abbe22
	github.com/webitel/protos/workflow v0.0.0-20220504085106-475035abbe22
	github.com/webitel/wlog v0.0.0-20190823170623-8cc283b29e3e
	golang.org/x/net v0.0.0-20220425223048-2871e0cb64e4
	golang.org/x/time v0.0.0-20191024005414-555d28b269f0
	google.golang.org/grpc v1.46.0
)

require (
	github.com/andres-erbsen/clock v0.0.0-20160526145045-9e14626cd129 // indirect
	github.com/armon/go-metrics v0.3.11 // indirect
	github.com/euskadi31/go-tokenizer v1.0.0 // indirect
	github.com/fatih/color v1.13.0 // indirect
	github.com/felixge/httpsnoop v1.0.2 // indirect
	github.com/go-sql-driver/mysql v1.6.0 // indirect
	github.com/google/uuid v1.3.0 // indirect
	github.com/gorilla/handlers v1.5.1 // indirect
	github.com/gorilla/mux v1.8.0 // indirect
	github.com/gorilla/websocket v1.5.0 // indirect
	github.com/grpc-ecosystem/grpc-gateway v1.16.0 // indirect
	github.com/hashicorp/consul/api v1.12.0 // indirect
	github.com/hashicorp/go-cleanhttp v0.5.2 // indirect
	github.com/hashicorp/go-hclog v1.2.0 // indirect
	github.com/hashicorp/go-immutable-radix v1.3.1 // indirect
	github.com/hashicorp/go-rootcerts v1.0.2 // indirect
	github.com/hashicorp/golang-lru v0.5.4 // indirect
	github.com/hashicorp/serf v0.9.7 // indirect
	github.com/jmoiron/sqlx v1.3.5 // indirect
	github.com/mattn/go-colorable v0.1.12 // indirect
	github.com/mattn/go-isatty v0.0.14 // indirect
	github.com/mattn/go-sqlite3 v1.14.6 // indirect
	github.com/mitchellh/go-homedir v1.1.0 // indirect
	github.com/mitchellh/mapstructure v1.5.0 // indirect
	github.com/nicksnyder/go-i18n v1.10.1 // indirect
	github.com/pelletier/go-toml v1.9.5 // indirect
	github.com/robertkrimen/otto v0.0.0-20211024170158-b87d35c0b86f // indirect
	github.com/satori/go.uuid v1.2.0 // indirect
	github.com/tidwall/gjson v1.14.1 // indirect
	github.com/tidwall/match v1.1.1 // indirect
	github.com/tidwall/pretty v1.2.0 // indirect
	github.com/webitel/protos/engine v0.0.0-20220504085106-475035abbe22 // indirect
	go.uber.org/atomic v1.9.0 // indirect
	go.uber.org/multierr v1.8.0 // indirect
	go.uber.org/ratelimit v0.2.0 // indirect
	go.uber.org/zap v1.21.0 // indirect
	golang.org/x/sys v0.0.0-20220503163025-988cb79eb6c6 // indirect
	golang.org/x/text v0.3.7 // indirect
	google.golang.org/genproto v0.0.0-20220503193339-ba3ae3f07e29 // indirect
	google.golang.org/protobuf v1.28.0 // indirect
	gopkg.in/alexcesaro/quotedprintable.v3 v3.0.0-20150716171945-2caba252f4dc // indirect
	gopkg.in/gomail.v2 v2.0.0-20160411212932-81ebce5c23df // indirect
	gopkg.in/natefinch/lumberjack.v2 v2.0.0 // indirect
	gopkg.in/sourcemap.v1 v1.0.5 // indirect
	gopkg.in/xmlpath.v2 v2.0.0-20150820204837-860cbeca3ebc // indirect
	gopkg.in/yaml.v2 v2.4.0 // indirect
)

replace google.golang.org/grpc => google.golang.org/grpc v1.27.0
