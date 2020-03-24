
protoc -I/usr/local/include -I./protos/cc/ -I$GOPATH/src/github.com/grpc-ecosystem/grpc-gateway/third_party/googleapis  \
  -I$GOPATH/src/github.com/grpc-ecosystem/grpc-gateway \
  --go_out=plugins=grpc:./cc ./protos/cc/*.proto