package dialing

type Dialing interface {
	Start()
	Stop()
	MakeCalls()
}
