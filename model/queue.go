package model

import (
	"encoding/json"
	"fmt"
)

const (
	QUEUE_TYPE_OFFLINE     = iota
	QUEUE_TYPE_INBOUND     // a
	QUEUE_TYPE_IVR         // r
	QUEUE_TYPE_PREVIEW     // a + r
	QUEUE_TYPE_PROGRESSIVE // a + r
	QUEUE_TYPE_PREDICT     // a +r
)

const (
	QUEUE_SIDE_FLOW   = "flow"
	QUEUE_SIDE_MEMBER = "member"
	QUEUE_SIDE_AGENT  = "agent"
)

const (
	QUEUE_SIDE_FIELD       = "cc_side"
	QUEUE_ID_FIELD         = "cc_queue_id"
	QUEUE_TEAM_ID_FIELD    = "cc_team_id"
	QUEUE_AGENT_ID_FIELD   = "cc_agent_id"
	QUEUE_UPDATED_AT_FIELD = "cc_queue_updated_at"

	QUEUE_MEMBER_PRIORITY = "cc_queue_member_priority"

	QUEUE_NAME_FIELD        = "cc_queue_name"
	QUEUE_TYPE_NAME_FIELD   = "cc_queue_type"
	QUEUE_MEMBER_ID_FIELD   = "cc_member_id"
	QUEUE_ATTEMPT_ID_FIELD  = "cc_attempt_id"
	QUEUE_RESOURCE_ID_FIELD = "cc_resource_id"
	QUEUE_NODE_ID_FIELD     = "cc_app_id"
)

type Queue struct {
	Id         int               `json:"id" db:"id"`
	DomainId   int64             `json:"domain_id" db:"domain_id"`
	DomainName string            `json:"domain_name" db:"domain_name"`
	Type       uint8             `json:"type" db:"type"`
	Name       string            `json:"name" db:"name"`
	Strategy   string            `json:"strategy" db:"strategy"`
	Payload    []byte            `json:"payload" db:"payload"`
	UpdatedAt  int64             `json:"updated_at" db:"updated_at"`
	MaxCalls   uint16            `json:"max_calls" db:"max_calls"`
	Variables  map[string]string `json:"variables" db:"variables"`
	TeamId     *int              `json:"team_id" db:"team_id"`
	Timeout    uint16            `json:"timeout" db:"timeout"`
	SchemaId   *int              `json:"schema_id" db:"schema_id"`
}

func (q *Queue) Channel() string {
	return "call" //FIXME  enum & queue_type
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

/* TODO
Max wait - not hangup
Max wait time with no agent - offline + onbreak
Agent stickli

*/

type QueueInboundSettings struct {
	QueueDialingSettings
	DiscardAbandonedAfter  int    `json:"discard_abandoned_after"`
	AbandonedResumeAllowed bool   `json:"abandoned_resume_allowed"`
	TimeBaseScore          string `json:"time_base_score"`
	MaxWait                int    `json:"max_wait"`
	MaxWaitWithNoAgent     int    `json:"max_wait_with_no_agent"`
	HangupOnRingingAgent   bool   `json:"hangup_on_ringing_agent"`
	MaxCallPerAgent        int    `json:"max_call_per_agent"`
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

func QueueInboundSettingsFromBytes(data []byte) QueueInboundSettings {
	var settings QueueInboundSettings
	json.Unmarshal(data, &settings)
	return settings
}

func (amd *QueueAmdSettings) ToArgs() string {
	return fmt.Sprintf("silence_threshold=%d maximum_word_length=%d maximum_number_of_words=%d between_words_silence=%d min_word_length=%d "+
		"total_analysis_time=%d after_greeting_silence=%d greeting=%d initial_silence=%d",
		amd.SilenceThreshold, amd.MaxWordLength, amd.MaxNumberOfWords, amd.BetweenWordsSilence, amd.MinWordLength, amd.TotalAnalysisTime,
		amd.AfterGreetingSilence, amd.Greeting, amd.InitialSilence)
}
