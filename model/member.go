package model

const (
	CAUSE_SYSTEM_SHUTDOWN = "SYSTEM_SHUTDOWN"
)

const (
	MEMBER_STATE_IDLE     = 0
	MEMBER_STATE_RESERVED = 1
)

type MemberJob struct {
	Id              int
	CommunicationId int
	QueueId         int
	MemberId        int
	ResourceId      int
	CreatedAt       int
	HangupAt        int
	BridgedAt       int
}
