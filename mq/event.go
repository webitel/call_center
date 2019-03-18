package mq

type Event interface {
	Name() string
	Id() string
	GetVariable(name string) (string, bool)
	GetIntVariable(name string) (int, bool)
}
