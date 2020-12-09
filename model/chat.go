package model

type ChatEvent struct {
	Name     string
	DomainId int64
	UserId   int64
	Data     map[string]interface{}
}

func (c ChatEvent) ConversationId() string {
	if k, ok := c.Data["conversation_id"].(string); ok {
		return k
	}

	return "todo"
}
