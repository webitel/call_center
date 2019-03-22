package model

import "encoding/json"

const (
	QUEUE_TYPE_INBOUND = iota
	QUEUE_TYPE_VOICE_BROADCAST
)

const (
	QUEUE_SIDE_MEMBER = "member"
	QUEUE_SIDE_AGENT  = "agent"
)

const (
	QUEUE_SIDE_FIELD        = "cc_side"
	QUEUE_ID_FIELD          = "cc_queue_id"
	QUEUE_NAME_FIELD        = "cc_queue_name"
	QUEUE_TYPE_NAME_FIELD   = "cc_queue_type"
	QUEUE_MEMBER_ID_FIELD   = "cc_member_id"
	QUEUE_ATTEMPT_ID_FIELD  = "cc_attempt_id"
	QUEUE_RESOURCE_ID_FIELD = "cc_resource_id"
	QUEUE_NODE_ID_FIELD     = "cc_node_id"
)

type Queue struct {
	Id        int               `json:"id" db:"id"`
	Type      int               `json:"type" db:"type"`
	Name      string            `json:"name" db:"name"`
	Strategy  string            `json:"strategy" db:"strategy"`
	Payload   []byte            `json:"payload" db:"payload"`
	UpdatedAt int64             `json:"updated_at" db:"updated_at"`
	MaxCalls  uint16            `json:"max_calls" db:"max_calls"`
	Variables map[string]string `json:"variables" db:"variables"`
	Timeout   uint16            `json:"timeout" db:"timeout"`
}

type QueueDialingSettings struct {
	MinCallDuration int  `json:"min_call_duration"`
	Recordings      bool `json:"recordings"`
}

type QueueAmdSettings struct {
	Enabled              bool   `json:"enabled"`
	AllowNotSure         bool   `json:"allow_not_sure"`
	MaxWordLength        uint16 `json:"max_word_length"`
	MaxNumberOfWords     uint16 `json:"max_number_of_words"`
	BetweenWordsSilence  uint16 `json:"between_words_silence"`
	MinWordLength        uint16 `json:"min_word_length"`
	TotalAnalysisTime    uint16 `json:"total_analysis_time"`
	SilenceThreshold     uint16 `json:"silence_threshold"`
	AfterGreetingSilence uint16 `json:"after_greeting_silence"`
	Greeting             uint16 `json:"greeting"`
	InitialSilence       uint16 `json:"initial_silence"`
	//TODO add playback file
}

type QueueVoiceSettings struct {
	QueueDialingSettings
	Amd *QueueAmdSettings `json:"amd"`
}

func QueueVoiceSettingsFromBytes(data []byte) QueueVoiceSettings {
	var settings QueueVoiceSettings
	json.Unmarshal(data, &settings)
	return settings
}
