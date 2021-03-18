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
	github.com/webitel/flow_manager v0.0.0-20210318110347-8e26118b62d1
	github.com/webitel/protos/cc v0.0.0-20210318110202-d914a54df431
	github.com/webitel/protos/workflow v0.0.0-20210318110202-d914a54df431
	github.com/webitel/wlog v0.0.0-20190823170623-8cc283b29e3e
	go.uber.org/atomic v1.7.0
	go.uber.org/ratelimit v0.1.0
	golang.org/x/net v0.0.0-20201031054903-ff519b6c9102
	google.golang.org/grpc v1.33.1
)
