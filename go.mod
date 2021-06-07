module github.com/webitel/call_center

go 1.15

require (
	github.com/go-gorp/gorp v2.2.0+incompatible
	github.com/golang/protobuf v1.4.3
	github.com/lib/pq v1.8.0
	github.com/olebedev/emitter v0.0.0-20190110104742-e8d1457e6aee
	github.com/pborman/uuid v1.2.1
	github.com/pkg/errors v0.9.1
	github.com/streadway/amqp v1.0.0
	github.com/webitel/engine v0.0.0-20201229081853-f0832da3adcc
	github.com/webitel/flow_manager v0.0.0-20210607084927-3df07b0e93aa
	github.com/webitel/protos/cc v0.0.0-20210521073006-4964fa579ea2
	github.com/webitel/protos/workflow v0.0.0-20210607084712-007db41ae25f
	github.com/webitel/wlog v0.0.0-20190823170623-8cc283b29e3e
	go.uber.org/atomic v1.7.0
	go.uber.org/ratelimit v0.2.0
	golang.org/x/net v0.0.0-20201031054903-ff519b6c9102
	google.golang.org/grpc v1.33.1
)
