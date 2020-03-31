// Code generated by protoc-gen-go. DO NOT EDIT.
// source: member.proto

package cc

import (
	context "context"
	fmt "fmt"
	proto "github.com/golang/protobuf/proto"
	_ "google.golang.org/genproto/googleapis/api/annotations"
	grpc "google.golang.org/grpc"
	codes "google.golang.org/grpc/codes"
	status "google.golang.org/grpc/status"
	math "math"
)

// Reference imports to suppress errors if they are not otherwise used.
var _ = proto.Marshal
var _ = fmt.Errorf
var _ = math.Inf

// This is a compile-time assertion to ensure that this generated file
// is compatible with the proto package it is being compiled against.
// A compilation error at this line likely means your copy of the
// proto package needs to be updated.
const _ = proto.ProtoPackageIsVersion3 // please upgrade the proto package

type DirectAgentToMemberRequest struct {
	MemberId             int64    `protobuf:"varint,1,opt,name=member_id,json=memberId,proto3" json:"member_id,omitempty"`
	AgentId              int64    `protobuf:"varint,2,opt,name=agent_id,json=agentId,proto3" json:"agent_id,omitempty"`
	DomainId             int64    `protobuf:"varint,3,opt,name=domain_id,json=domainId,proto3" json:"domain_id,omitempty"`
	XXX_NoUnkeyedLiteral struct{} `json:"-"`
	XXX_unrecognized     []byte   `json:"-"`
	XXX_sizecache        int32    `json:"-"`
}

func (m *DirectAgentToMemberRequest) Reset()         { *m = DirectAgentToMemberRequest{} }
func (m *DirectAgentToMemberRequest) String() string { return proto.CompactTextString(m) }
func (*DirectAgentToMemberRequest) ProtoMessage()    {}
func (*DirectAgentToMemberRequest) Descriptor() ([]byte, []int) {
	return fileDescriptor_9b9836b7e13de206, []int{0}
}

func (m *DirectAgentToMemberRequest) XXX_Unmarshal(b []byte) error {
	return xxx_messageInfo_DirectAgentToMemberRequest.Unmarshal(m, b)
}
func (m *DirectAgentToMemberRequest) XXX_Marshal(b []byte, deterministic bool) ([]byte, error) {
	return xxx_messageInfo_DirectAgentToMemberRequest.Marshal(b, m, deterministic)
}
func (m *DirectAgentToMemberRequest) XXX_Merge(src proto.Message) {
	xxx_messageInfo_DirectAgentToMemberRequest.Merge(m, src)
}
func (m *DirectAgentToMemberRequest) XXX_Size() int {
	return xxx_messageInfo_DirectAgentToMemberRequest.Size(m)
}
func (m *DirectAgentToMemberRequest) XXX_DiscardUnknown() {
	xxx_messageInfo_DirectAgentToMemberRequest.DiscardUnknown(m)
}

var xxx_messageInfo_DirectAgentToMemberRequest proto.InternalMessageInfo

func (m *DirectAgentToMemberRequest) GetMemberId() int64 {
	if m != nil {
		return m.MemberId
	}
	return 0
}

func (m *DirectAgentToMemberRequest) GetAgentId() int64 {
	if m != nil {
		return m.AgentId
	}
	return 0
}

func (m *DirectAgentToMemberRequest) GetDomainId() int64 {
	if m != nil {
		return m.DomainId
	}
	return 0
}

type DirectAgentToMemberResponse struct {
	AttemptId            int64    `protobuf:"varint,1,opt,name=attempt_id,json=attemptId,proto3" json:"attempt_id,omitempty"`
	XXX_NoUnkeyedLiteral struct{} `json:"-"`
	XXX_unrecognized     []byte   `json:"-"`
	XXX_sizecache        int32    `json:"-"`
}

func (m *DirectAgentToMemberResponse) Reset()         { *m = DirectAgentToMemberResponse{} }
func (m *DirectAgentToMemberResponse) String() string { return proto.CompactTextString(m) }
func (*DirectAgentToMemberResponse) ProtoMessage()    {}
func (*DirectAgentToMemberResponse) Descriptor() ([]byte, []int) {
	return fileDescriptor_9b9836b7e13de206, []int{1}
}

func (m *DirectAgentToMemberResponse) XXX_Unmarshal(b []byte) error {
	return xxx_messageInfo_DirectAgentToMemberResponse.Unmarshal(m, b)
}
func (m *DirectAgentToMemberResponse) XXX_Marshal(b []byte, deterministic bool) ([]byte, error) {
	return xxx_messageInfo_DirectAgentToMemberResponse.Marshal(b, m, deterministic)
}
func (m *DirectAgentToMemberResponse) XXX_Merge(src proto.Message) {
	xxx_messageInfo_DirectAgentToMemberResponse.Merge(m, src)
}
func (m *DirectAgentToMemberResponse) XXX_Size() int {
	return xxx_messageInfo_DirectAgentToMemberResponse.Size(m)
}
func (m *DirectAgentToMemberResponse) XXX_DiscardUnknown() {
	xxx_messageInfo_DirectAgentToMemberResponse.DiscardUnknown(m)
}

var xxx_messageInfo_DirectAgentToMemberResponse proto.InternalMessageInfo

func (m *DirectAgentToMemberResponse) GetAttemptId() int64 {
	if m != nil {
		return m.AttemptId
	}
	return 0
}

type CallJoinToQueueRequest struct {
	CallId               string   `protobuf:"bytes,1,opt,name=call_id,json=callId,proto3" json:"call_id,omitempty"`
	QueueName            string   `protobuf:"bytes,2,opt,name=queue_name,json=queueName,proto3" json:"queue_name,omitempty"`
	QueueId              int64    `protobuf:"varint,3,opt,name=queue_id,json=queueId,proto3" json:"queue_id,omitempty"`
	Priority             int32    `protobuf:"varint,4,opt,name=priority,proto3" json:"priority,omitempty"`
	DomainId             int64    `protobuf:"varint,100,opt,name=domain_id,json=domainId,proto3" json:"domain_id,omitempty"`
	XXX_NoUnkeyedLiteral struct{} `json:"-"`
	XXX_unrecognized     []byte   `json:"-"`
	XXX_sizecache        int32    `json:"-"`
}

func (m *CallJoinToQueueRequest) Reset()         { *m = CallJoinToQueueRequest{} }
func (m *CallJoinToQueueRequest) String() string { return proto.CompactTextString(m) }
func (*CallJoinToQueueRequest) ProtoMessage()    {}
func (*CallJoinToQueueRequest) Descriptor() ([]byte, []int) {
	return fileDescriptor_9b9836b7e13de206, []int{2}
}

func (m *CallJoinToQueueRequest) XXX_Unmarshal(b []byte) error {
	return xxx_messageInfo_CallJoinToQueueRequest.Unmarshal(m, b)
}
func (m *CallJoinToQueueRequest) XXX_Marshal(b []byte, deterministic bool) ([]byte, error) {
	return xxx_messageInfo_CallJoinToQueueRequest.Marshal(b, m, deterministic)
}
func (m *CallJoinToQueueRequest) XXX_Merge(src proto.Message) {
	xxx_messageInfo_CallJoinToQueueRequest.Merge(m, src)
}
func (m *CallJoinToQueueRequest) XXX_Size() int {
	return xxx_messageInfo_CallJoinToQueueRequest.Size(m)
}
func (m *CallJoinToQueueRequest) XXX_DiscardUnknown() {
	xxx_messageInfo_CallJoinToQueueRequest.DiscardUnknown(m)
}

var xxx_messageInfo_CallJoinToQueueRequest proto.InternalMessageInfo

func (m *CallJoinToQueueRequest) GetCallId() string {
	if m != nil {
		return m.CallId
	}
	return ""
}

func (m *CallJoinToQueueRequest) GetQueueName() string {
	if m != nil {
		return m.QueueName
	}
	return ""
}

func (m *CallJoinToQueueRequest) GetQueueId() int64 {
	if m != nil {
		return m.QueueId
	}
	return 0
}

func (m *CallJoinToQueueRequest) GetPriority() int32 {
	if m != nil {
		return m.Priority
	}
	return 0
}

func (m *CallJoinToQueueRequest) GetDomainId() int64 {
	if m != nil {
		return m.DomainId
	}
	return 0
}

type CallJoinToQueueResponse struct {
	Status               string   `protobuf:"bytes,1,opt,name=status,proto3" json:"status,omitempty"`
	XXX_NoUnkeyedLiteral struct{} `json:"-"`
	XXX_unrecognized     []byte   `json:"-"`
	XXX_sizecache        int32    `json:"-"`
}

func (m *CallJoinToQueueResponse) Reset()         { *m = CallJoinToQueueResponse{} }
func (m *CallJoinToQueueResponse) String() string { return proto.CompactTextString(m) }
func (*CallJoinToQueueResponse) ProtoMessage()    {}
func (*CallJoinToQueueResponse) Descriptor() ([]byte, []int) {
	return fileDescriptor_9b9836b7e13de206, []int{3}
}

func (m *CallJoinToQueueResponse) XXX_Unmarshal(b []byte) error {
	return xxx_messageInfo_CallJoinToQueueResponse.Unmarshal(m, b)
}
func (m *CallJoinToQueueResponse) XXX_Marshal(b []byte, deterministic bool) ([]byte, error) {
	return xxx_messageInfo_CallJoinToQueueResponse.Marshal(b, m, deterministic)
}
func (m *CallJoinToQueueResponse) XXX_Merge(src proto.Message) {
	xxx_messageInfo_CallJoinToQueueResponse.Merge(m, src)
}
func (m *CallJoinToQueueResponse) XXX_Size() int {
	return xxx_messageInfo_CallJoinToQueueResponse.Size(m)
}
func (m *CallJoinToQueueResponse) XXX_DiscardUnknown() {
	xxx_messageInfo_CallJoinToQueueResponse.DiscardUnknown(m)
}

var xxx_messageInfo_CallJoinToQueueResponse proto.InternalMessageInfo

func (m *CallJoinToQueueResponse) GetStatus() string {
	if m != nil {
		return m.Status
	}
	return ""
}

type AttemptResultRequest struct {
	QueueId              int32             `protobuf:"varint,1,opt,name=queue_id,json=queueId,proto3" json:"queue_id,omitempty"`
	MemberId             int32             `protobuf:"varint,2,opt,name=member_id,json=memberId,proto3" json:"member_id,omitempty"`
	AttemptId            int32             `protobuf:"varint,3,opt,name=attempt_id,json=attemptId,proto3" json:"attempt_id,omitempty"`
	Status               string            `protobuf:"bytes,4,opt,name=status,proto3" json:"status,omitempty"`
	MinOfferingAt        int64             `protobuf:"varint,5,opt,name=min_offering_at,json=minOfferingAt,proto3" json:"min_offering_at,omitempty"`
	ExpireAt             int64             `protobuf:"varint,6,opt,name=expire_at,json=expireAt,proto3" json:"expire_at,omitempty"`
	Variables            map[string]string `protobuf:"bytes,7,rep,name=variables,proto3" json:"variables,omitempty" protobuf_key:"bytes,1,opt,name=key,proto3" protobuf_val:"bytes,2,opt,name=value,proto3"`
	Display              bool              `protobuf:"varint,8,opt,name=display,proto3" json:"display,omitempty"`
	Description          string            `protobuf:"bytes,9,opt,name=description,proto3" json:"description,omitempty"`
	TransferQueueId      int64             `protobuf:"varint,10,opt,name=transfer_queue_id,json=transferQueueId,proto3" json:"transfer_queue_id,omitempty"`
	XXX_NoUnkeyedLiteral struct{}          `json:"-"`
	XXX_unrecognized     []byte            `json:"-"`
	XXX_sizecache        int32             `json:"-"`
}

func (m *AttemptResultRequest) Reset()         { *m = AttemptResultRequest{} }
func (m *AttemptResultRequest) String() string { return proto.CompactTextString(m) }
func (*AttemptResultRequest) ProtoMessage()    {}
func (*AttemptResultRequest) Descriptor() ([]byte, []int) {
	return fileDescriptor_9b9836b7e13de206, []int{4}
}

func (m *AttemptResultRequest) XXX_Unmarshal(b []byte) error {
	return xxx_messageInfo_AttemptResultRequest.Unmarshal(m, b)
}
func (m *AttemptResultRequest) XXX_Marshal(b []byte, deterministic bool) ([]byte, error) {
	return xxx_messageInfo_AttemptResultRequest.Marshal(b, m, deterministic)
}
func (m *AttemptResultRequest) XXX_Merge(src proto.Message) {
	xxx_messageInfo_AttemptResultRequest.Merge(m, src)
}
func (m *AttemptResultRequest) XXX_Size() int {
	return xxx_messageInfo_AttemptResultRequest.Size(m)
}
func (m *AttemptResultRequest) XXX_DiscardUnknown() {
	xxx_messageInfo_AttemptResultRequest.DiscardUnknown(m)
}

var xxx_messageInfo_AttemptResultRequest proto.InternalMessageInfo

func (m *AttemptResultRequest) GetQueueId() int32 {
	if m != nil {
		return m.QueueId
	}
	return 0
}

func (m *AttemptResultRequest) GetMemberId() int32 {
	if m != nil {
		return m.MemberId
	}
	return 0
}

func (m *AttemptResultRequest) GetAttemptId() int32 {
	if m != nil {
		return m.AttemptId
	}
	return 0
}

func (m *AttemptResultRequest) GetStatus() string {
	if m != nil {
		return m.Status
	}
	return ""
}

func (m *AttemptResultRequest) GetMinOfferingAt() int64 {
	if m != nil {
		return m.MinOfferingAt
	}
	return 0
}

func (m *AttemptResultRequest) GetExpireAt() int64 {
	if m != nil {
		return m.ExpireAt
	}
	return 0
}

func (m *AttemptResultRequest) GetVariables() map[string]string {
	if m != nil {
		return m.Variables
	}
	return nil
}

func (m *AttemptResultRequest) GetDisplay() bool {
	if m != nil {
		return m.Display
	}
	return false
}

func (m *AttemptResultRequest) GetDescription() string {
	if m != nil {
		return m.Description
	}
	return ""
}

func (m *AttemptResultRequest) GetTransferQueueId() int64 {
	if m != nil {
		return m.TransferQueueId
	}
	return 0
}

type AttemptResultResponse struct {
	Status               string   `protobuf:"bytes,1,opt,name=status,proto3" json:"status,omitempty"`
	XXX_NoUnkeyedLiteral struct{} `json:"-"`
	XXX_unrecognized     []byte   `json:"-"`
	XXX_sizecache        int32    `json:"-"`
}

func (m *AttemptResultResponse) Reset()         { *m = AttemptResultResponse{} }
func (m *AttemptResultResponse) String() string { return proto.CompactTextString(m) }
func (*AttemptResultResponse) ProtoMessage()    {}
func (*AttemptResultResponse) Descriptor() ([]byte, []int) {
	return fileDescriptor_9b9836b7e13de206, []int{5}
}

func (m *AttemptResultResponse) XXX_Unmarshal(b []byte) error {
	return xxx_messageInfo_AttemptResultResponse.Unmarshal(m, b)
}
func (m *AttemptResultResponse) XXX_Marshal(b []byte, deterministic bool) ([]byte, error) {
	return xxx_messageInfo_AttemptResultResponse.Marshal(b, m, deterministic)
}
func (m *AttemptResultResponse) XXX_Merge(src proto.Message) {
	xxx_messageInfo_AttemptResultResponse.Merge(m, src)
}
func (m *AttemptResultResponse) XXX_Size() int {
	return xxx_messageInfo_AttemptResultResponse.Size(m)
}
func (m *AttemptResultResponse) XXX_DiscardUnknown() {
	xxx_messageInfo_AttemptResultResponse.DiscardUnknown(m)
}

var xxx_messageInfo_AttemptResultResponse proto.InternalMessageInfo

func (m *AttemptResultResponse) GetStatus() string {
	if m != nil {
		return m.Status
	}
	return ""
}

func init() {
	proto.RegisterType((*DirectAgentToMemberRequest)(nil), "cc.DirectAgentToMemberRequest")
	proto.RegisterType((*DirectAgentToMemberResponse)(nil), "cc.DirectAgentToMemberResponse")
	proto.RegisterType((*CallJoinToQueueRequest)(nil), "cc.CallJoinToQueueRequest")
	proto.RegisterType((*CallJoinToQueueResponse)(nil), "cc.CallJoinToQueueResponse")
	proto.RegisterType((*AttemptResultRequest)(nil), "cc.AttemptResultRequest")
	proto.RegisterMapType((map[string]string)(nil), "cc.AttemptResultRequest.VariablesEntry")
	proto.RegisterType((*AttemptResultResponse)(nil), "cc.AttemptResultResponse")
}

func init() { proto.RegisterFile("member.proto", fileDescriptor_9b9836b7e13de206) }

var fileDescriptor_9b9836b7e13de206 = []byte{
	// 617 bytes of a gzipped FileDescriptorProto
	0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0xff, 0x7c, 0x54, 0xcd, 0x6e, 0xd3, 0x40,
	0x10, 0xc6, 0x49, 0x9b, 0xc4, 0x53, 0x4a, 0x61, 0x29, 0xad, 0xeb, 0xf2, 0x13, 0xe5, 0x00, 0x11,
	0x87, 0x58, 0x94, 0x0b, 0x42, 0xbd, 0x44, 0x50, 0x89, 0x54, 0xfc, 0xd5, 0x54, 0x88, 0x5b, 0xb4,
	0xb5, 0xa7, 0xd1, 0x0a, 0x7b, 0xd7, 0xdd, 0xdd, 0x54, 0x44, 0x55, 0x2f, 0xbc, 0x02, 0x12, 0x4f,
	0xc0, 0x3b, 0xf0, 0x1a, 0x48, 0xbc, 0x02, 0x0f, 0x82, 0x76, 0x37, 0xce, 0x4f, 0x49, 0xb8, 0x79,
	0xe6, 0xdb, 0xd9, 0xf9, 0xbe, 0x99, 0x6f, 0x0d, 0xd7, 0x73, 0xcc, 0x4f, 0x50, 0x76, 0x0a, 0x29,
	0xb4, 0x20, 0x95, 0x24, 0x09, 0xef, 0x0e, 0x84, 0x18, 0x64, 0x18, 0xd1, 0x82, 0x45, 0x94, 0x73,
	0xa1, 0xa9, 0x66, 0x82, 0x2b, 0x77, 0xa2, 0x75, 0x06, 0xe1, 0x4b, 0x26, 0x31, 0xd1, 0xdd, 0x01,
	0x72, 0x7d, 0x2c, 0xde, 0xd8, 0xf2, 0x18, 0xcf, 0x86, 0xa8, 0x34, 0xd9, 0x05, 0xdf, 0xdd, 0xd7,
	0x67, 0x69, 0xe0, 0x35, 0xbd, 0x76, 0x35, 0x6e, 0xb8, 0x44, 0x2f, 0x25, 0x3b, 0xd0, 0xa0, 0xa6,
	0xc8, 0x60, 0x15, 0x8b, 0xd5, 0x6d, 0xdc, 0x4b, 0x4d, 0x5d, 0x2a, 0x72, 0xca, 0xb8, 0xc1, 0xaa,
	0xae, 0xce, 0x25, 0x7a, 0x69, 0x6b, 0x1f, 0x76, 0x17, 0xb6, 0x54, 0x85, 0xe0, 0x0a, 0xc9, 0x3d,
	0x00, 0xaa, 0x35, 0xe6, 0x85, 0x9e, 0x36, 0xf5, 0xc7, 0x99, 0x5e, 0xda, 0xfa, 0xe1, 0xc1, 0xd6,
	0x0b, 0x9a, 0x65, 0x87, 0x82, 0xf1, 0x63, 0x71, 0x34, 0xc4, 0x21, 0x96, 0x6c, 0xb7, 0xa1, 0x9e,
	0xd0, 0x2c, 0x2b, 0xcb, 0xfc, 0xb8, 0x66, 0xc2, 0x5e, 0x6a, 0xae, 0x3c, 0x33, 0x07, 0xfb, 0x9c,
	0xe6, 0x68, 0xb9, 0xfa, 0xb1, 0x6f, 0x33, 0x6f, 0x69, 0x8e, 0x46, 0x88, 0x83, 0x27, 0x64, 0xeb,
	0x36, 0xee, 0xa5, 0x24, 0x84, 0x46, 0x21, 0x99, 0x90, 0x4c, 0x8f, 0x82, 0x95, 0xa6, 0xd7, 0x5e,
	0x8d, 0x27, 0xf1, 0xbc, 0xc8, 0xf4, 0x8a, 0xc8, 0x27, 0xb0, 0xfd, 0x0f, 0xcb, 0xb1, 0xc0, 0x2d,
	0xa8, 0x29, 0x4d, 0xf5, 0x50, 0x95, 0x2c, 0x5d, 0xd4, 0xfa, 0x59, 0x85, 0xcd, 0xae, 0xd3, 0x19,
	0xa3, 0x1a, 0x66, 0xba, 0xd4, 0x35, 0xcb, 0xcf, 0xb3, 0x24, 0x26, 0xfc, 0xe6, 0x16, 0x54, 0x71,
	0x04, 0x27, 0x0b, 0x9a, 0x9f, 0x64, 0xd5, 0xa2, 0xd3, 0x49, 0xce, 0xf0, 0x58, 0x99, 0xe5, 0x41,
	0x1e, 0xc2, 0x46, 0xce, 0x78, 0x5f, 0x9c, 0x9e, 0xa2, 0x64, 0x7c, 0xd0, 0xa7, 0x3a, 0x58, 0xb5,
	0xea, 0xd6, 0x73, 0xc6, 0xdf, 0x8d, 0xb3, 0x5d, 0x6b, 0x0e, 0xfc, 0x52, 0x30, 0x89, 0xe6, 0x44,
	0xcd, 0xe9, 0x77, 0x89, 0xae, 0x26, 0x07, 0xe0, 0x9f, 0x53, 0xc9, 0xe8, 0x49, 0x86, 0x2a, 0xa8,
	0x37, 0xab, 0xed, 0xb5, 0xbd, 0x47, 0x9d, 0x24, 0xe9, 0x2c, 0x12, 0xd8, 0xf9, 0x58, 0x9e, 0x3c,
	0xe0, 0x5a, 0x8e, 0xe2, 0x69, 0x25, 0x09, 0xa0, 0x9e, 0x32, 0x55, 0x64, 0x74, 0x14, 0x34, 0x9a,
	0x5e, 0xbb, 0x11, 0x97, 0x21, 0x69, 0xc2, 0x5a, 0x8a, 0x2a, 0x91, 0xac, 0x30, 0x76, 0x0e, 0x7c,
	0x2b, 0x61, 0x36, 0x45, 0x1e, 0xc3, 0x2d, 0x2d, 0x29, 0x57, 0xa7, 0x28, 0xfb, 0x93, 0xf9, 0x81,
	0xe5, 0xb9, 0x51, 0x02, 0x47, 0x6e, 0x8e, 0xe1, 0x3e, 0xdc, 0x98, 0x27, 0x41, 0x6e, 0x42, 0xf5,
	0x33, 0x8e, 0xc6, 0x2b, 0x32, 0x9f, 0x64, 0x13, 0x56, 0xcf, 0x69, 0x36, 0x2c, 0x0d, 0xe4, 0x82,
	0xe7, 0x95, 0x67, 0x5e, 0x2b, 0x82, 0x3b, 0x57, 0x74, 0xfd, 0x7f, 0xd5, 0x7b, 0xbf, 0x2a, 0xb0,
	0xee, 0x6c, 0xff, 0x01, 0xe5, 0x39, 0x4b, 0x90, 0x7c, 0xf7, 0x60, 0x7d, 0xee, 0x0e, 0x12, 0x2c,
	0x1b, 0x57, 0xb8, 0xb3, 0x00, 0x71, 0x0d, 0x5b, 0xef, 0xbf, 0xfe, 0xfe, 0xf3, 0xad, 0x72, 0xb8,
	0xf7, 0x2a, 0xb2, 0x2f, 0x21, 0x41, 0xae, 0x51, 0x46, 0x56, 0xbd, 0x8a, 0x2e, 0xca, 0x29, 0x5c,
	0x46, 0xce, 0x23, 0x2a, 0xba, 0x98, 0xb8, 0xe7, 0x32, 0x1a, 0x3b, 0x43, 0x45, 0x17, 0x53, 0xd7,
	0x5c, 0x92, 0xd7, 0xb0, 0x71, 0xc5, 0xc8, 0x24, 0x34, 0xfd, 0x17, 0xbf, 0xc1, 0x70, 0x77, 0x21,
	0x36, 0x66, 0x77, 0x8d, 0x7c, 0x82, 0xdb, 0x0b, 0xde, 0x3e, 0xb9, 0x6f, 0xaa, 0x96, 0xff, 0x87,
	0xc2, 0x07, 0x4b, 0xf1, 0xf2, 0xe6, 0x93, 0x9a, 0xfd, 0x9f, 0x3d, 0xfd, 0x1b, 0x00, 0x00, 0xff,
	0xff, 0x33, 0x12, 0xce, 0x8e, 0x01, 0x05, 0x00, 0x00,
}

// Reference imports to suppress errors if they are not otherwise used.
var _ context.Context
var _ grpc.ClientConn

// This is a compile-time assertion to ensure that this generated file
// is compatible with the grpc package it is being compiled against.
const _ = grpc.SupportPackageIsVersion4

// MemberServiceClient is the client API for MemberService service.
//
// For semantics around ctx use and closing/ending streaming RPCs, please refer to https://godoc.org/google.golang.org/grpc#ClientConn.NewStream.
type MemberServiceClient interface {
	AttemptResult(ctx context.Context, in *AttemptResultRequest, opts ...grpc.CallOption) (*AttemptResultResponse, error)
	CallJoinToQueue(ctx context.Context, in *CallJoinToQueueRequest, opts ...grpc.CallOption) (*CallJoinToQueueResponse, error)
	DirectAgentToMember(ctx context.Context, in *DirectAgentToMemberRequest, opts ...grpc.CallOption) (*DirectAgentToMemberResponse, error)
}

type memberServiceClient struct {
	cc *grpc.ClientConn
}

func NewMemberServiceClient(cc *grpc.ClientConn) MemberServiceClient {
	return &memberServiceClient{cc}
}

func (c *memberServiceClient) AttemptResult(ctx context.Context, in *AttemptResultRequest, opts ...grpc.CallOption) (*AttemptResultResponse, error) {
	out := new(AttemptResultResponse)
	err := c.cc.Invoke(ctx, "/cc.MemberService/AttemptResult", in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *memberServiceClient) CallJoinToQueue(ctx context.Context, in *CallJoinToQueueRequest, opts ...grpc.CallOption) (*CallJoinToQueueResponse, error) {
	out := new(CallJoinToQueueResponse)
	err := c.cc.Invoke(ctx, "/cc.MemberService/CallJoinToQueue", in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *memberServiceClient) DirectAgentToMember(ctx context.Context, in *DirectAgentToMemberRequest, opts ...grpc.CallOption) (*DirectAgentToMemberResponse, error) {
	out := new(DirectAgentToMemberResponse)
	err := c.cc.Invoke(ctx, "/cc.MemberService/DirectAgentToMember", in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

// MemberServiceServer is the server API for MemberService service.
type MemberServiceServer interface {
	AttemptResult(context.Context, *AttemptResultRequest) (*AttemptResultResponse, error)
	CallJoinToQueue(context.Context, *CallJoinToQueueRequest) (*CallJoinToQueueResponse, error)
	DirectAgentToMember(context.Context, *DirectAgentToMemberRequest) (*DirectAgentToMemberResponse, error)
}

// UnimplementedMemberServiceServer can be embedded to have forward compatible implementations.
type UnimplementedMemberServiceServer struct {
}

func (*UnimplementedMemberServiceServer) AttemptResult(ctx context.Context, req *AttemptResultRequest) (*AttemptResultResponse, error) {
	return nil, status.Errorf(codes.Unimplemented, "method AttemptResult not implemented")
}
func (*UnimplementedMemberServiceServer) CallJoinToQueue(ctx context.Context, req *CallJoinToQueueRequest) (*CallJoinToQueueResponse, error) {
	return nil, status.Errorf(codes.Unimplemented, "method CallJoinToQueue not implemented")
}
func (*UnimplementedMemberServiceServer) DirectAgentToMember(ctx context.Context, req *DirectAgentToMemberRequest) (*DirectAgentToMemberResponse, error) {
	return nil, status.Errorf(codes.Unimplemented, "method DirectAgentToMember not implemented")
}

func RegisterMemberServiceServer(s *grpc.Server, srv MemberServiceServer) {
	s.RegisterService(&_MemberService_serviceDesc, srv)
}

func _MemberService_AttemptResult_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(AttemptResultRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(MemberServiceServer).AttemptResult(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: "/cc.MemberService/AttemptResult",
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(MemberServiceServer).AttemptResult(ctx, req.(*AttemptResultRequest))
	}
	return interceptor(ctx, in, info, handler)
}

func _MemberService_CallJoinToQueue_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(CallJoinToQueueRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(MemberServiceServer).CallJoinToQueue(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: "/cc.MemberService/CallJoinToQueue",
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(MemberServiceServer).CallJoinToQueue(ctx, req.(*CallJoinToQueueRequest))
	}
	return interceptor(ctx, in, info, handler)
}

func _MemberService_DirectAgentToMember_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(DirectAgentToMemberRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(MemberServiceServer).DirectAgentToMember(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: "/cc.MemberService/DirectAgentToMember",
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(MemberServiceServer).DirectAgentToMember(ctx, req.(*DirectAgentToMemberRequest))
	}
	return interceptor(ctx, in, info, handler)
}

var _MemberService_serviceDesc = grpc.ServiceDesc{
	ServiceName: "cc.MemberService",
	HandlerType: (*MemberServiceServer)(nil),
	Methods: []grpc.MethodDesc{
		{
			MethodName: "AttemptResult",
			Handler:    _MemberService_AttemptResult_Handler,
		},
		{
			MethodName: "CallJoinToQueue",
			Handler:    _MemberService_CallJoinToQueue_Handler,
		},
		{
			MethodName: "DirectAgentToMember",
			Handler:    _MemberService_DirectAgentToMember_Handler,
		},
	},
	Streams:  []grpc.StreamDesc{},
	Metadata: "member.proto",
}
