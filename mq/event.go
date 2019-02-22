package mq

type Event interface {
	Name() string
	Id() string
}
