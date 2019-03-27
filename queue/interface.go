package queue

type Dialing interface {
	Start()
	Stop()

	//OnHangupCall(memberId int64, e Event)
}

type Event interface {
	Name() string
	Id() string
	GetVariable(name string) (string, bool)
}
