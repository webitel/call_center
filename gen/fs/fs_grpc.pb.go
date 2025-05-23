// Code generated by protoc-gen-go-grpc. DO NOT EDIT.
// versions:
// - protoc-gen-go-grpc v1.3.0
// - protoc             (unknown)
// source: fs.proto

package fs

import (
	context "context"
	grpc "google.golang.org/grpc"
	codes "google.golang.org/grpc/codes"
	status "google.golang.org/grpc/status"
)

// This is a compile-time assertion to ensure that this generated file
// is compatible with the grpc package it is being compiled against.
// Requires gRPC-Go v1.32.0 or later.
const _ = grpc.SupportPackageIsVersion7

const (
	Api_Originate_FullMethodName          = "/fs.Api/Originate"
	Api_Execute_FullMethodName            = "/fs.Api/Execute"
	Api_SetVariables_FullMethodName       = "/fs.Api/SetVariables"
	Api_Bridge_FullMethodName             = "/fs.Api/Bridge"
	Api_BridgeCall_FullMethodName         = "/fs.Api/BridgeCall"
	Api_StopPlayback_FullMethodName       = "/fs.Api/StopPlayback"
	Api_Hangup_FullMethodName             = "/fs.Api/Hangup"
	Api_HangupMatchingVars_FullMethodName = "/fs.Api/HangupMatchingVars"
	Api_Queue_FullMethodName              = "/fs.Api/Queue"
	Api_HangupMany_FullMethodName         = "/fs.Api/HangupMany"
	Api_Hold_FullMethodName               = "/fs.Api/Hold"
	Api_UnHold_FullMethodName             = "/fs.Api/UnHold"
	Api_SetProfileVar_FullMethodName      = "/fs.Api/SetProfileVar"
	Api_ConfirmPush_FullMethodName        = "/fs.Api/ConfirmPush"
	Api_Broadcast_FullMethodName          = "/fs.Api/Broadcast"
	Api_SetEavesdropState_FullMethodName  = "/fs.Api/SetEavesdropState"
	Api_BlindTransfer_FullMethodName      = "/fs.Api/BlindTransfer"
	Api_BreakPark_FullMethodName          = "/fs.Api/BreakPark"
)

// ApiClient is the client API for Api service.
//
// For semantics around ctx use and closing/ending streaming RPCs, please refer to https://pkg.go.dev/google.golang.org/grpc/?tab=doc#ClientConn.NewStream.
type ApiClient interface {
	Originate(ctx context.Context, in *OriginateRequest, opts ...grpc.CallOption) (*OriginateResponse, error)
	Execute(ctx context.Context, in *ExecuteRequest, opts ...grpc.CallOption) (*ExecuteResponse, error)
	SetVariables(ctx context.Context, in *SetVariablesRequest, opts ...grpc.CallOption) (*SetVariablesResponse, error)
	Bridge(ctx context.Context, in *BridgeRequest, opts ...grpc.CallOption) (*BridgeResponse, error)
	BridgeCall(ctx context.Context, in *BridgeCallRequest, opts ...grpc.CallOption) (*BridgeCallResponse, error)
	StopPlayback(ctx context.Context, in *StopPlaybackRequest, opts ...grpc.CallOption) (*StopPlaybackResponse, error)
	Hangup(ctx context.Context, in *HangupRequest, opts ...grpc.CallOption) (*HangupResponse, error)
	HangupMatchingVars(ctx context.Context, in *HangupMatchingVarsReqeust, opts ...grpc.CallOption) (*HangupMatchingVarsResponse, error)
	Queue(ctx context.Context, in *QueueRequest, opts ...grpc.CallOption) (*QueueResponse, error)
	HangupMany(ctx context.Context, in *HangupManyRequest, opts ...grpc.CallOption) (*HangupManyResponse, error)
	Hold(ctx context.Context, in *HoldRequest, opts ...grpc.CallOption) (*HoldResponse, error)
	UnHold(ctx context.Context, in *UnHoldRequest, opts ...grpc.CallOption) (*UnHoldResponse, error)
	SetProfileVar(ctx context.Context, in *SetProfileVarRequest, opts ...grpc.CallOption) (*SetProfileVarResponse, error)
	ConfirmPush(ctx context.Context, in *ConfirmPushRequest, opts ...grpc.CallOption) (*ConfirmPushResponse, error)
	Broadcast(ctx context.Context, in *BroadcastRequest, opts ...grpc.CallOption) (*BroadcastResponse, error)
	SetEavesdropState(ctx context.Context, in *SetEavesdropStateRequest, opts ...grpc.CallOption) (*SetEavesdropStateResponse, error)
	BlindTransfer(ctx context.Context, in *BlindTransferRequest, opts ...grpc.CallOption) (*BlindTransferResponse, error)
	BreakPark(ctx context.Context, in *BreakParkRequest, opts ...grpc.CallOption) (*BreakParkResponse, error)
}

type apiClient struct {
	cc grpc.ClientConnInterface
}

func NewApiClient(cc grpc.ClientConnInterface) ApiClient {
	return &apiClient{cc}
}

func (c *apiClient) Originate(ctx context.Context, in *OriginateRequest, opts ...grpc.CallOption) (*OriginateResponse, error) {
	out := new(OriginateResponse)
	err := c.cc.Invoke(ctx, Api_Originate_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *apiClient) Execute(ctx context.Context, in *ExecuteRequest, opts ...grpc.CallOption) (*ExecuteResponse, error) {
	out := new(ExecuteResponse)
	err := c.cc.Invoke(ctx, Api_Execute_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *apiClient) SetVariables(ctx context.Context, in *SetVariablesRequest, opts ...grpc.CallOption) (*SetVariablesResponse, error) {
	out := new(SetVariablesResponse)
	err := c.cc.Invoke(ctx, Api_SetVariables_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *apiClient) Bridge(ctx context.Context, in *BridgeRequest, opts ...grpc.CallOption) (*BridgeResponse, error) {
	out := new(BridgeResponse)
	err := c.cc.Invoke(ctx, Api_Bridge_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *apiClient) BridgeCall(ctx context.Context, in *BridgeCallRequest, opts ...grpc.CallOption) (*BridgeCallResponse, error) {
	out := new(BridgeCallResponse)
	err := c.cc.Invoke(ctx, Api_BridgeCall_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *apiClient) StopPlayback(ctx context.Context, in *StopPlaybackRequest, opts ...grpc.CallOption) (*StopPlaybackResponse, error) {
	out := new(StopPlaybackResponse)
	err := c.cc.Invoke(ctx, Api_StopPlayback_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *apiClient) Hangup(ctx context.Context, in *HangupRequest, opts ...grpc.CallOption) (*HangupResponse, error) {
	out := new(HangupResponse)
	err := c.cc.Invoke(ctx, Api_Hangup_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *apiClient) HangupMatchingVars(ctx context.Context, in *HangupMatchingVarsReqeust, opts ...grpc.CallOption) (*HangupMatchingVarsResponse, error) {
	out := new(HangupMatchingVarsResponse)
	err := c.cc.Invoke(ctx, Api_HangupMatchingVars_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *apiClient) Queue(ctx context.Context, in *QueueRequest, opts ...grpc.CallOption) (*QueueResponse, error) {
	out := new(QueueResponse)
	err := c.cc.Invoke(ctx, Api_Queue_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *apiClient) HangupMany(ctx context.Context, in *HangupManyRequest, opts ...grpc.CallOption) (*HangupManyResponse, error) {
	out := new(HangupManyResponse)
	err := c.cc.Invoke(ctx, Api_HangupMany_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *apiClient) Hold(ctx context.Context, in *HoldRequest, opts ...grpc.CallOption) (*HoldResponse, error) {
	out := new(HoldResponse)
	err := c.cc.Invoke(ctx, Api_Hold_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *apiClient) UnHold(ctx context.Context, in *UnHoldRequest, opts ...grpc.CallOption) (*UnHoldResponse, error) {
	out := new(UnHoldResponse)
	err := c.cc.Invoke(ctx, Api_UnHold_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *apiClient) SetProfileVar(ctx context.Context, in *SetProfileVarRequest, opts ...grpc.CallOption) (*SetProfileVarResponse, error) {
	out := new(SetProfileVarResponse)
	err := c.cc.Invoke(ctx, Api_SetProfileVar_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *apiClient) ConfirmPush(ctx context.Context, in *ConfirmPushRequest, opts ...grpc.CallOption) (*ConfirmPushResponse, error) {
	out := new(ConfirmPushResponse)
	err := c.cc.Invoke(ctx, Api_ConfirmPush_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *apiClient) Broadcast(ctx context.Context, in *BroadcastRequest, opts ...grpc.CallOption) (*BroadcastResponse, error) {
	out := new(BroadcastResponse)
	err := c.cc.Invoke(ctx, Api_Broadcast_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *apiClient) SetEavesdropState(ctx context.Context, in *SetEavesdropStateRequest, opts ...grpc.CallOption) (*SetEavesdropStateResponse, error) {
	out := new(SetEavesdropStateResponse)
	err := c.cc.Invoke(ctx, Api_SetEavesdropState_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *apiClient) BlindTransfer(ctx context.Context, in *BlindTransferRequest, opts ...grpc.CallOption) (*BlindTransferResponse, error) {
	out := new(BlindTransferResponse)
	err := c.cc.Invoke(ctx, Api_BlindTransfer_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *apiClient) BreakPark(ctx context.Context, in *BreakParkRequest, opts ...grpc.CallOption) (*BreakParkResponse, error) {
	out := new(BreakParkResponse)
	err := c.cc.Invoke(ctx, Api_BreakPark_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

// ApiServer is the server API for Api service.
// All implementations must embed UnimplementedApiServer
// for forward compatibility
type ApiServer interface {
	Originate(context.Context, *OriginateRequest) (*OriginateResponse, error)
	Execute(context.Context, *ExecuteRequest) (*ExecuteResponse, error)
	SetVariables(context.Context, *SetVariablesRequest) (*SetVariablesResponse, error)
	Bridge(context.Context, *BridgeRequest) (*BridgeResponse, error)
	BridgeCall(context.Context, *BridgeCallRequest) (*BridgeCallResponse, error)
	StopPlayback(context.Context, *StopPlaybackRequest) (*StopPlaybackResponse, error)
	Hangup(context.Context, *HangupRequest) (*HangupResponse, error)
	HangupMatchingVars(context.Context, *HangupMatchingVarsReqeust) (*HangupMatchingVarsResponse, error)
	Queue(context.Context, *QueueRequest) (*QueueResponse, error)
	HangupMany(context.Context, *HangupManyRequest) (*HangupManyResponse, error)
	Hold(context.Context, *HoldRequest) (*HoldResponse, error)
	UnHold(context.Context, *UnHoldRequest) (*UnHoldResponse, error)
	SetProfileVar(context.Context, *SetProfileVarRequest) (*SetProfileVarResponse, error)
	ConfirmPush(context.Context, *ConfirmPushRequest) (*ConfirmPushResponse, error)
	Broadcast(context.Context, *BroadcastRequest) (*BroadcastResponse, error)
	SetEavesdropState(context.Context, *SetEavesdropStateRequest) (*SetEavesdropStateResponse, error)
	BlindTransfer(context.Context, *BlindTransferRequest) (*BlindTransferResponse, error)
	BreakPark(context.Context, *BreakParkRequest) (*BreakParkResponse, error)
	mustEmbedUnimplementedApiServer()
}

// UnimplementedApiServer must be embedded to have forward compatible implementations.
type UnimplementedApiServer struct {
}

func (UnimplementedApiServer) Originate(context.Context, *OriginateRequest) (*OriginateResponse, error) {
	return nil, status.Errorf(codes.Unimplemented, "method Originate not implemented")
}
func (UnimplementedApiServer) Execute(context.Context, *ExecuteRequest) (*ExecuteResponse, error) {
	return nil, status.Errorf(codes.Unimplemented, "method Execute not implemented")
}
func (UnimplementedApiServer) SetVariables(context.Context, *SetVariablesRequest) (*SetVariablesResponse, error) {
	return nil, status.Errorf(codes.Unimplemented, "method SetVariables not implemented")
}
func (UnimplementedApiServer) Bridge(context.Context, *BridgeRequest) (*BridgeResponse, error) {
	return nil, status.Errorf(codes.Unimplemented, "method Bridge not implemented")
}
func (UnimplementedApiServer) BridgeCall(context.Context, *BridgeCallRequest) (*BridgeCallResponse, error) {
	return nil, status.Errorf(codes.Unimplemented, "method BridgeCall not implemented")
}
func (UnimplementedApiServer) StopPlayback(context.Context, *StopPlaybackRequest) (*StopPlaybackResponse, error) {
	return nil, status.Errorf(codes.Unimplemented, "method StopPlayback not implemented")
}
func (UnimplementedApiServer) Hangup(context.Context, *HangupRequest) (*HangupResponse, error) {
	return nil, status.Errorf(codes.Unimplemented, "method Hangup not implemented")
}
func (UnimplementedApiServer) HangupMatchingVars(context.Context, *HangupMatchingVarsReqeust) (*HangupMatchingVarsResponse, error) {
	return nil, status.Errorf(codes.Unimplemented, "method HangupMatchingVars not implemented")
}
func (UnimplementedApiServer) Queue(context.Context, *QueueRequest) (*QueueResponse, error) {
	return nil, status.Errorf(codes.Unimplemented, "method Queue not implemented")
}
func (UnimplementedApiServer) HangupMany(context.Context, *HangupManyRequest) (*HangupManyResponse, error) {
	return nil, status.Errorf(codes.Unimplemented, "method HangupMany not implemented")
}
func (UnimplementedApiServer) Hold(context.Context, *HoldRequest) (*HoldResponse, error) {
	return nil, status.Errorf(codes.Unimplemented, "method Hold not implemented")
}
func (UnimplementedApiServer) UnHold(context.Context, *UnHoldRequest) (*UnHoldResponse, error) {
	return nil, status.Errorf(codes.Unimplemented, "method UnHold not implemented")
}
func (UnimplementedApiServer) SetProfileVar(context.Context, *SetProfileVarRequest) (*SetProfileVarResponse, error) {
	return nil, status.Errorf(codes.Unimplemented, "method SetProfileVar not implemented")
}
func (UnimplementedApiServer) ConfirmPush(context.Context, *ConfirmPushRequest) (*ConfirmPushResponse, error) {
	return nil, status.Errorf(codes.Unimplemented, "method ConfirmPush not implemented")
}
func (UnimplementedApiServer) Broadcast(context.Context, *BroadcastRequest) (*BroadcastResponse, error) {
	return nil, status.Errorf(codes.Unimplemented, "method Broadcast not implemented")
}
func (UnimplementedApiServer) SetEavesdropState(context.Context, *SetEavesdropStateRequest) (*SetEavesdropStateResponse, error) {
	return nil, status.Errorf(codes.Unimplemented, "method SetEavesdropState not implemented")
}
func (UnimplementedApiServer) BlindTransfer(context.Context, *BlindTransferRequest) (*BlindTransferResponse, error) {
	return nil, status.Errorf(codes.Unimplemented, "method BlindTransfer not implemented")
}
func (UnimplementedApiServer) BreakPark(context.Context, *BreakParkRequest) (*BreakParkResponse, error) {
	return nil, status.Errorf(codes.Unimplemented, "method BreakPark not implemented")
}
func (UnimplementedApiServer) mustEmbedUnimplementedApiServer() {}

// UnsafeApiServer may be embedded to opt out of forward compatibility for this service.
// Use of this interface is not recommended, as added methods to ApiServer will
// result in compilation errors.
type UnsafeApiServer interface {
	mustEmbedUnimplementedApiServer()
}

func RegisterApiServer(s grpc.ServiceRegistrar, srv ApiServer) {
	s.RegisterService(&Api_ServiceDesc, srv)
}

func _Api_Originate_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(OriginateRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(ApiServer).Originate(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: Api_Originate_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(ApiServer).Originate(ctx, req.(*OriginateRequest))
	}
	return interceptor(ctx, in, info, handler)
}

func _Api_Execute_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(ExecuteRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(ApiServer).Execute(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: Api_Execute_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(ApiServer).Execute(ctx, req.(*ExecuteRequest))
	}
	return interceptor(ctx, in, info, handler)
}

func _Api_SetVariables_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(SetVariablesRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(ApiServer).SetVariables(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: Api_SetVariables_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(ApiServer).SetVariables(ctx, req.(*SetVariablesRequest))
	}
	return interceptor(ctx, in, info, handler)
}

func _Api_Bridge_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(BridgeRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(ApiServer).Bridge(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: Api_Bridge_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(ApiServer).Bridge(ctx, req.(*BridgeRequest))
	}
	return interceptor(ctx, in, info, handler)
}

func _Api_BridgeCall_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(BridgeCallRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(ApiServer).BridgeCall(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: Api_BridgeCall_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(ApiServer).BridgeCall(ctx, req.(*BridgeCallRequest))
	}
	return interceptor(ctx, in, info, handler)
}

func _Api_StopPlayback_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(StopPlaybackRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(ApiServer).StopPlayback(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: Api_StopPlayback_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(ApiServer).StopPlayback(ctx, req.(*StopPlaybackRequest))
	}
	return interceptor(ctx, in, info, handler)
}

func _Api_Hangup_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(HangupRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(ApiServer).Hangup(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: Api_Hangup_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(ApiServer).Hangup(ctx, req.(*HangupRequest))
	}
	return interceptor(ctx, in, info, handler)
}

func _Api_HangupMatchingVars_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(HangupMatchingVarsReqeust)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(ApiServer).HangupMatchingVars(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: Api_HangupMatchingVars_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(ApiServer).HangupMatchingVars(ctx, req.(*HangupMatchingVarsReqeust))
	}
	return interceptor(ctx, in, info, handler)
}

func _Api_Queue_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(QueueRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(ApiServer).Queue(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: Api_Queue_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(ApiServer).Queue(ctx, req.(*QueueRequest))
	}
	return interceptor(ctx, in, info, handler)
}

func _Api_HangupMany_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(HangupManyRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(ApiServer).HangupMany(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: Api_HangupMany_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(ApiServer).HangupMany(ctx, req.(*HangupManyRequest))
	}
	return interceptor(ctx, in, info, handler)
}

func _Api_Hold_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(HoldRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(ApiServer).Hold(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: Api_Hold_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(ApiServer).Hold(ctx, req.(*HoldRequest))
	}
	return interceptor(ctx, in, info, handler)
}

func _Api_UnHold_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(UnHoldRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(ApiServer).UnHold(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: Api_UnHold_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(ApiServer).UnHold(ctx, req.(*UnHoldRequest))
	}
	return interceptor(ctx, in, info, handler)
}

func _Api_SetProfileVar_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(SetProfileVarRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(ApiServer).SetProfileVar(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: Api_SetProfileVar_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(ApiServer).SetProfileVar(ctx, req.(*SetProfileVarRequest))
	}
	return interceptor(ctx, in, info, handler)
}

func _Api_ConfirmPush_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(ConfirmPushRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(ApiServer).ConfirmPush(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: Api_ConfirmPush_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(ApiServer).ConfirmPush(ctx, req.(*ConfirmPushRequest))
	}
	return interceptor(ctx, in, info, handler)
}

func _Api_Broadcast_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(BroadcastRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(ApiServer).Broadcast(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: Api_Broadcast_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(ApiServer).Broadcast(ctx, req.(*BroadcastRequest))
	}
	return interceptor(ctx, in, info, handler)
}

func _Api_SetEavesdropState_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(SetEavesdropStateRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(ApiServer).SetEavesdropState(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: Api_SetEavesdropState_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(ApiServer).SetEavesdropState(ctx, req.(*SetEavesdropStateRequest))
	}
	return interceptor(ctx, in, info, handler)
}

func _Api_BlindTransfer_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(BlindTransferRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(ApiServer).BlindTransfer(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: Api_BlindTransfer_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(ApiServer).BlindTransfer(ctx, req.(*BlindTransferRequest))
	}
	return interceptor(ctx, in, info, handler)
}

func _Api_BreakPark_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(BreakParkRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(ApiServer).BreakPark(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: Api_BreakPark_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(ApiServer).BreakPark(ctx, req.(*BreakParkRequest))
	}
	return interceptor(ctx, in, info, handler)
}

// Api_ServiceDesc is the grpc.ServiceDesc for Api service.
// It's only intended for direct use with grpc.RegisterService,
// and not to be introspected or modified (even as a copy)
var Api_ServiceDesc = grpc.ServiceDesc{
	ServiceName: "fs.Api",
	HandlerType: (*ApiServer)(nil),
	Methods: []grpc.MethodDesc{
		{
			MethodName: "Originate",
			Handler:    _Api_Originate_Handler,
		},
		{
			MethodName: "Execute",
			Handler:    _Api_Execute_Handler,
		},
		{
			MethodName: "SetVariables",
			Handler:    _Api_SetVariables_Handler,
		},
		{
			MethodName: "Bridge",
			Handler:    _Api_Bridge_Handler,
		},
		{
			MethodName: "BridgeCall",
			Handler:    _Api_BridgeCall_Handler,
		},
		{
			MethodName: "StopPlayback",
			Handler:    _Api_StopPlayback_Handler,
		},
		{
			MethodName: "Hangup",
			Handler:    _Api_Hangup_Handler,
		},
		{
			MethodName: "HangupMatchingVars",
			Handler:    _Api_HangupMatchingVars_Handler,
		},
		{
			MethodName: "Queue",
			Handler:    _Api_Queue_Handler,
		},
		{
			MethodName: "HangupMany",
			Handler:    _Api_HangupMany_Handler,
		},
		{
			MethodName: "Hold",
			Handler:    _Api_Hold_Handler,
		},
		{
			MethodName: "UnHold",
			Handler:    _Api_UnHold_Handler,
		},
		{
			MethodName: "SetProfileVar",
			Handler:    _Api_SetProfileVar_Handler,
		},
		{
			MethodName: "ConfirmPush",
			Handler:    _Api_ConfirmPush_Handler,
		},
		{
			MethodName: "Broadcast",
			Handler:    _Api_Broadcast_Handler,
		},
		{
			MethodName: "SetEavesdropState",
			Handler:    _Api_SetEavesdropState_Handler,
		},
		{
			MethodName: "BlindTransfer",
			Handler:    _Api_BlindTransfer_Handler,
		},
		{
			MethodName: "BreakPark",
			Handler:    _Api_BreakPark_Handler,
		},
	},
	Streams:  []grpc.StreamDesc{},
	Metadata: "fs.proto",
}
