package rabbit

type REvent struct {
	EventName string `json:"Event-Name"`
	Uuid      string `json:"Unique-ID"`
}

func (e *REvent) Name() string {
	return e.EventName
}

func (e *REvent) Id() string {
	return e.Uuid
}
