package app

import (
	"context"
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"net"
	"net/http"
	"strconv"
	"time"
)

type GrpcServer struct {
	srv *grpc.Server
	lis net.Listener
	log *wlog.Logger
}

func (grpc *GrpcServer) GetPublicInterface() (string, int) {
	h, p, _ := net.SplitHostPort(grpc.lis.Addr().String())
	if h == "::" {
		h = model.GetPublicAddr()
	}
	port, _ := strconv.Atoi(p)
	return h, port
}

func GetUnaryInterceptor(log *wlog.Logger) grpc.UnaryServerInterceptor {
	return func(ctx context.Context,
		req interface{},
		info *grpc.UnaryServerInfo,
		handler grpc.UnaryHandler) (interface{}, error) {
		start := time.Now()

		h, err := handler(ctx, req)

		since := time.Since(start)

		if err != nil {
			log.Error(fmt.Sprintf("method %s duration %s, error: %v", info.FullMethod, since, err.Error()),
				wlog.Err(err),
				wlog.Duration("duration", since),
				wlog.String("method", info.FullMethod),
			)

			switch err.(type) {
			case *model.AppError:
				e := err.(*model.AppError)
				return h, status.Error(httpCodeToGrpc(e.StatusCode), e.ToJson())
			default:
				return h, err
			}
		} else {
			log.Debug(fmt.Sprintf("method %s duration %s, OK", info.FullMethod, since),
				wlog.Duration("duration", since),
				wlog.String("method", info.FullMethod),
			)
		}

		return h, err
	}
}

func httpCodeToGrpc(c int) codes.Code {
	switch c {
	case http.StatusBadRequest:
		return codes.InvalidArgument
	case http.StatusAccepted:
		return codes.ResourceExhausted
	case http.StatusUnauthorized:
		return codes.Unauthenticated
	case http.StatusForbidden:
		return codes.PermissionDenied
	default:
		return codes.Internal

	}
}

func NewGrpcServer(settings model.ServerSettings, log *wlog.Logger) *GrpcServer {
	address := fmt.Sprintf("%s:%d", settings.Address, settings.Port)
	lis, err := net.Listen(settings.Network, address)
	if err != nil {
		panic(err.Error())
	}

	grpcLog := log.With(
		wlog.Namespace("context"),
		wlog.String("protocol", "grpc"),
		wlog.String("address", lis.Addr().String()),
	)
	return &GrpcServer{
		lis: lis,
		srv: grpc.NewServer(
			grpc.UnaryInterceptor(GetUnaryInterceptor(grpcLog)),
		),
		log: grpcLog,
	}
}

func (s *GrpcServer) Server() *grpc.Server {
	return s.srv
}

func (a *App) StartGrpcServer() error {
	go func() {
		defer a.GrpcServer.log.Debug(fmt.Sprintf("[grpc] close server listening"))
		a.GrpcServer.log.Debug(fmt.Sprintf("[grpc] server listening %s", a.GrpcServer.lis.Addr().String()))
		err := a.GrpcServer.srv.Serve(a.GrpcServer.lis)
		if err != nil {
			//FIXME
			panic(err.Error())
		}
	}()

	return nil
}
