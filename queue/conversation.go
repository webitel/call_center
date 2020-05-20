package queue

import (
	"sync"
)

const (
	ConversationStateWaiting = "waiting"
	ConversationStateBridged = "bridged"
)

type Participant struct {
	//conversation model.Conversation
	//participant  model.Participant
	id string
	sync.Mutex
	state     string
	stateCh   chan string
	BridgedAt int64
}

func NewParticipant(id string) *Participant {
	return &Participant{
		id:      id,
		state:   ConversationStateWaiting,
		stateCh: make(chan string),
	}
}

func (c *Participant) Id() string {
	return c.id
}

func (c *Participant) Close() {
	close(c.stateCh)
}

func (c *Participant) SetStateBridged(bridgedAt int64) {
	c.Lock()
	c.BridgedAt = bridgedAt
	c.state = ConversationStateBridged
	c.Unlock()
	c.stateCh <- ConversationStateBridged
}

func (c *Participant) StateChannel() <-chan string {
	return c.stateCh
}
