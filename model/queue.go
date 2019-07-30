package model

import (
	"encoding/json"
	"fmt"
)

const (
	QUEUE_TYPE_INBOUND = iota
	QUEUE_TYPE_IVR
	QUEUE_TYPE_PREVIEW
	QUEUE_TYPE_PROGRESSIVE
	QUEUE_TYPE_PREDICT
)

const (
	QUEUE_SIDE_MEMBER = "member"
	QUEUE_SIDE_AGENT  = "agent"
)

const (
	QUEUE_SIDE_FIELD       = "cc_side"
	QUEUE_ID_FIELD         = "cc_queue_id"
	QUEUE_UPDATED_AT_FIELD = "cc_queue_updated_at"

	QUEUE_MEMBER_PRIORITY = "cc_queue_member_priority"

	QUEUE_NAME_FIELD        = "cc_queue_name"
	QUEUE_TYPE_NAME_FIELD   = "cc_queue_type"
	QUEUE_MEMBER_ID_FIELD   = "cc_member_id"
	QUEUE_ATTEMPT_ID_FIELD  = "cc_attempt_id"
	QUEUE_RESOURCE_ID_FIELD = "cc_resource_id"
	QUEUE_ROUTING_ID_FIELD  = "cc_routing_id"
	QUEUE_NODE_ID_FIELD     = "cc_node_id"
)

type Queue struct {
	Id        int               `json:"id" db:"id"`
	Type      uint8             `json:"type" db:"type"`
	Name      string            `json:"name" db:"name"`
	Strategy  string            `json:"strategy" db:"strategy"`
	Payload   []byte            `json:"payload" db:"payload"`
	UpdatedAt int64             `json:"updated_at" db:"updated_at"`
	MaxCalls  uint16            `json:"max_calls" db:"max_calls"`
	Variables map[string]string `json:"variables" db:"variables"`
	Timeout   uint16            `json:"timeout" db:"timeout"`
}

type QueueDialingSettings struct {
	MinCallDuration      int      `json:"min_call_duration"`
	Recordings           bool     `json:"recordings"`
	CauseErrorIds        []string `json:"cause_error_ids"`
	CauseRetryIds        []string `json:"cause_retry_ids"`
	CauseSuccessIds      []string `json:"cause_success_ids"`
	CauseMinusAttemptIds []string `json:"cause_minus_attempt_ids"`
}

type QueueAmdSettings struct {
	Enabled                 bool   `json:"enabled"`
	AllowNotSure            bool   `json:"allow_not_sure"`
	MaxWordLength           uint16 `json:"max_word_length"`
	MaxNumberOfWords        uint16 `json:"max_number_of_words"`
	BetweenWordsSilence     uint16 `json:"between_words_silence"`
	MinWordLength           uint16 `json:"min_word_length"`
	TotalAnalysisTime       uint16 `json:"total_analysis_time"`
	SilenceThreshold        uint16 `json:"silence_threshold"`
	AfterGreetingSilence    uint16 `json:"after_greeting_silence"`
	Greeting                uint16 `json:"greeting"`
	InitialSilence          uint16 `json:"initial_silence"`
	PlaybackFileSilenceTime uint16 `json:"playback_file_silence_time"`
	PlaybackFileUri         string `json:"playback_file_uri"`
}

type QueueCallbackSettings struct {
	Enabled bool  `json:"enabled"`
	Timeout int32 `json:"timeout"`
}

type QueueAgentsSettings struct {
}

type QueueIVRSettings struct {
	QueueDialingSettings
	Amd *QueueAmdSettings `json:"amd"`
}

type QueuePreviewSettings struct {
	QueueDialingSettings
	Callback *QueueCallbackSettings `json:"callback"`
	Agents   *QueueAgentsSettings   `json:"agents"`
}

type QueueProgressiveSettings struct {
	QueueDialingSettings
	Callback *QueueCallbackSettings `json:"callback"`
	Agents   *QueueAgentsSettings   `json:"agents"`
	Amd      *QueueAmdSettings      `json:"amd"`
}

type QueuePredictiveSettings struct {
	QueueDialingSettings
	Callback *QueueCallbackSettings `json:"callback"`
	Agents   *QueueAgentsSettings   `json:"agents"`
	Amd      *QueueAmdSettings      `json:"amd"`
}

func (queueSettings *QueueDialingSettings) InCauseSuccess(id string) bool {
	for _, v := range queueSettings.CauseSuccessIds {
		if v == id {
			return true
		}
	}
	return false
}

func (queueSettings *QueueDialingSettings) InCauseRetry(id string) bool {
	for _, v := range queueSettings.CauseRetryIds {
		if v == id {
			return true
		}
	}
	return false
}

func (queueSettings *QueueDialingSettings) InCauseMinusAttempt(id string) bool {
	for _, v := range queueSettings.CauseMinusAttemptIds {
		if v == id {
			return true
		}
	}
	return false
}

func (queueSettings *QueueDialingSettings) InCauseError(id string) bool {
	for _, v := range queueSettings.CauseErrorIds {
		if v == id {
			return true
		}
	}
	return false
}

func QueueIVRSettingsFromBytes(data []byte) QueueIVRSettings {
	var settings QueueIVRSettings
	json.Unmarshal(data, &settings)
	return settings
}

func (amd *QueueAmdSettings) ToArgs() string {
	return fmt.Sprintf("silence_threshold=%d maximum_word_length=%d maximum_number_of_words=%d between_words_silence=%d min_word_length=%d "+
		"total_analysis_time=%d after_greeting_silence=%d greeting=%d initial_silence=%d",
		amd.SilenceThreshold, amd.MaxWordLength, amd.MaxNumberOfWords, amd.BetweenWordsSilence, amd.MinWordLength, amd.TotalAnalysisTime,
		amd.AfterGreetingSilence, amd.Greeting, amd.InitialSilence)
}
