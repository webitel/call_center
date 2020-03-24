module github.com/webitel/call_center

go 1.13

require (
	github.com/go-gorp/gorp v2.2.0+incompatible
	github.com/golang/protobuf v1.3.2
	github.com/hashicorp/consul/api v1.3.0
	github.com/lib/pq v1.3.0
	github.com/nicksnyder/go-i18n v1.10.1
	github.com/pborman/uuid v1.2.0
	github.com/pkg/errors v0.9.1
	github.com/streadway/amqp v0.0.0-20200108173154-1c71cc93ed71
	github.com/webitel/engine v0.0.0-20200319094448-64bed4f54b55
	github.com/webitel/flow_manager v0.0.0-20200316104623-3a49d908443f
	github.com/webitel/wlog v0.0.0-20190823170623-8cc283b29e3e
	go.uber.org/atomic v1.5.1
	go.uber.org/ratelimit v0.1.0
	golang.org/x/net v0.0.0-20200114155413-6afb5195e5aa
	google.golang.org/grpc v1.26.0
)

replace github.com/webitel/flow_manager => ../../webitel/flow_manager
