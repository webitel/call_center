package queue

type Dialing interface {
	Start()
	Stop()
	Manager() *QueueManager
}

type Event interface {
	Name() string
	Id() string
	GetVariable(name string) (string, bool)
}
