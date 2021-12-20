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
	github.com/webitel/engine v0.0.0-20210618144234-cc4ac480c364
	github.com/webitel/flow_manager v0.0.0-20211215135948-e40a30f9583a
	github.com/webitel/protos/cc v0.0.0-20211214105739-b73f33646458
	github.com/webitel/protos/engine v0.0.0-20211214105739-b73f33646458 // indirect
	github.com/webitel/protos/workflow v0.0.0-20211214105739-b73f33646458
	github.com/webitel/wlog v0.0.0-20190823170623-8cc283b29e3e
	golang.org/x/net v0.0.0-20201031054903-ff519b6c9102
	golang.org/x/time v0.0.0-20191024005414-555d28b269f0
	google.golang.org/grpc v1.33.1
)
