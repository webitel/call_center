package dialing

type Dialing interface {
	Start()
	Stop()

	//OnHangupCall(memberId int64, e Event)
}

type Event interface {
}
