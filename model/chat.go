package model

type InboundChatQueue struct {
	AttemptId      int64             `json:"attempt_id" db:"attempt_id"`
	QueueId        int               `json:"queue_id" db:"queue_id"`
	QueueUpdatedAt int64             `json:"queue_updated_at" db:"queue_updated_at"`
	Destination    []byte            `json:"destination" db:"destination"`
	Variables      map[string]string `json:"variables" db:"variables"`
	Name           string            `json:"name" db:"name"`
	TeamUpdatedAt  *int64            `json:"team_updated_at" db:"team_updated_at"`
	//ListCommunicationId *int64 `json:"list_communication_id" db:"list_communication_id"`

	ConversationId        string `json:"conversation_id" db:"conversation_id"`
	ConversationCreatedAt int64  `json:"conversation_created_at" db:"conversation_created_at"`
}

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

	return ""
}

func (c ChatEvent) Timestamp() int64 {
	i, _ := c.Data["timestamp"].(float64)
	return int64(i)
}

func (c ChatEvent) Cause() string {
	if v, ok := c.Data["cause"].(string); ok {
		return v
	}
	return ""
}

func (c ChatEvent) ChannelId() string {
	if i, ok := c.Data["member"].(map[string]interface{}); ok {
		res, _ := i["id"].(string)
		return res
	}

	return ""
}

func (c ChatEvent) MessageChannelId() string {
	if k, ok := c.Data["channel_id"].(string); ok {
		return k
	}

	return ""
}

func (c ChatEvent) InviteId() string {
	i, _ := c.Data["invite_id"].(string)
	return i
}
