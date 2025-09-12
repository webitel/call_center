package model

import (
	"encoding/json"
	"fmt"
	"strings"
)

const (
	QueueTypeOfflineCall     = iota
	QueueTypeInboundCall     // a
	QueueTypeIVRCall         // r
	QueueTypePreviewCall     // a + r
	QueueTypeProgressiveCall // a + r
	QueueTypePredictCall     // a +r
	QueueTypeInboundChat
	QueueTypeAgentTask
	QueueTypeOutboundTask
	QueueTypeOutboundCall
)

const (
	QUEUE_SIDE_FLOW   = "flow"
	QUEUE_SIDE_MEMBER = "member"
	QUEUE_SIDE_AGENT  = "agent"
)

const (
	QueueChannelCall    = "call"
	QueueChannelChat    = "chat"
	QueueChannelTask    = "task"
	QueueChannelOutCall = "out_call"
)

const (
	QUEUE_SIDE_FIELD       = "cc_side"
	QUEUE_ID_FIELD         = "cc_queue_id"
	QUEUE_TEAM_ID_FIELD    = "cc_team_id"
	QUEUE_AGENT_ID_FIELD   = "cc_agent_id"
	QUEUE_UPDATED_AT_FIELD = "cc_queue_updated_at"

	QUEUE_NAME_FIELD        = "cc_queue_name"
	QUEUE_TYPE_NAME_FIELD   = "cc_queue_type"
	QUEUE_MEMBER_ID_FIELD   = "cc_member_id"
	QUEUE_ATTEMPT_ID_FIELD  = "cc_attempt_id"
	QUEUE_RESOURCE_ID_FIELD = "cc_resource_id"
	QUEUE_NODE_ID_FIELD     = "cc_app_id"
	QUEUE_ATTEMPT_SEQ       = "cc_attempt_seq"
)

const (
	AgentTimeout   LeaveCause = "agent_timeout"
	ClientTimeout             = "client_timeout"
	SilenceTimeout            = "silence_timeout"
)

type LeaveCause string

const (
	ClientLeave CloseCause = "client_leave"
)

type CloseCause string

const (
	QueueAutoAnswerVariable = "wbt_auto_answer"
	QueueManualDistribute   = "cc_manual_distribution"
)

type RingtoneFile struct {
	Id   int    `json:"id"`
	Type string `json:"type"`
}

func (r *RingtoneFile) Uri(domainId int64) string {
	return RingtoneUri(domainId, r.Id, r.Type)
}

func RingtoneUri(domainId int64, id int, mimeType string) string {
	switch mimeType {
	case "audio/mp3", "audio/mpeg":
		return fmt.Sprintf("shout://$${cdr_url}/sys/media/%d/stream?domain_id=%d&.mp3", id, domainId)
	case "audio/wav":
		return fmt.Sprintf("http_cache://http://$${cdr_url}/sys/media/%d/stream?domain_id=%d&.wav", id, domainId)
	default:
		return ""
	}
}

var ToneList = map[string]string{
	"none":       "",
	"default":    "L=1;%(500,500,1000)",
	"at1":        "v=-7;%(100,0,941.0,1477.0)",
	"at2":        "v=-7;>=2;+=.1;%(140,0,350,440)",
	"australian": "L=1;%(200,100,400,425)",
	"egypt":      "L=1;%(200,100,475,375)",
	"germany":    "L=1;%(500,0,425)",
	"france":     "L=1;%(150,350,440)",
	"spain":      "L=1;%(150,300,425)",
	"uk":         "L=1;%(200,100,400,450)",
	"us":         "L=1;%(100,200,440,480)",
}

type Queue struct {
	Id                   int               `json:"id" db:"id"`
	DomainId             int64             `json:"domain_id" db:"domain_id"`
	DomainName           string            `json:"domain_name" db:"domain_name"`
	Type                 uint8             `json:"type" db:"type"`
	Name                 string            `json:"name" db:"name"`
	Strategy             string            `json:"strategy" db:"strategy"`
	Payload              []byte            `json:"payload" db:"payload"`
	UpdatedAt            int64             `json:"updated_at" db:"updated_at"`
	Variables            map[string]string `json:"variables" db:"variables"`
	TeamId               *int              `json:"team_id" db:"team_id"`
	RingtoneId           *int              `json:"ringtone_id" db:"ringtone_id"`
	RingtoneType         *string           `json:"ringtone_type" db:"ringtone_type"`
	SchemaId             *int              `json:"schema_id" db:"schema_id"`
	DoSchemaId           *int32            `json:"do_schema_id" db:"do_schema_id"`
	AfterSchemaId        *int32            `json:"after_schema_id" db:"after_schema_id"`
	Processing           bool              `json:"processing" db:"processing"`
	ProcessingSec        uint32            `json:"processing_sec" db:"processing_sec"`
	ProcessingRenewalSec uint32            `json:"processing_renewal_sec" db:"processing_renewal_sec"`
	Endless              bool              `json:"endless" db:"endless"`
	Hooks                []*QueueHook      `json:"hooks" db:"hooks"`
	GranteeId            *int              `json:"grantee_id" db:"grantee_id"`
	HoldMusic            *RingtoneFile     `json:"hold_music" db:"hold_music"`
	FormSchemaId         *int              `json:"form_schema_id" db:"form_schema_id"`
	AmdPlaybackFile      *RingtoneFile     `json:"amd_playback_file" db:"amd_playback_file"`

	IsProlongationEnabled      bool   `json:"prolongation_enabled" db:"prolongation_enabled"`
	ProlongationRepeats        uint32 `json:"prolongation_repeats_number" db:"prolongation_repeats_number"`
	ProlongationSec            uint32 `json:"prolongation_time_sec" db:"prolongation_time_sec"`
	IsProlongationTimeoutRetry bool   `json:"prolongation_is_timeout_retry" db:"prolongation_is_timeout_retry"`
}

func (q *Queue) Channel() string {
	switch q.Type {
	case QueueTypeInboundChat:
		return QueueChannelChat
	case QueueTypeAgentTask, QueueTypeOutboundTask:
		return QueueChannelTask
	case QueueTypeOutboundCall:
		return QueueChannelOutCall
	default:
		return QueueChannelCall
	}
}

type QueueAmdSettings struct {
	Enabled      bool     `json:"enabled"`
	Ai           bool     `json:"ai"`
	PositiveTags []string `json:"positive"`

	AllowNotSure         bool   `json:"allow_not_sure"`
	SilenceNotSure       bool   `json:"silence_not_sure"`
	MaxWordLength        uint16 `json:"max_word_length"`
	MaxNumberOfWords     uint16 `json:"max_number_of_words"`
	BetweenWordsSilence  uint16 `json:"between_words_silence"`
	MinWordLength        uint16 `json:"min_word_length"`
	TotalAnalysisTime    uint16 `json:"total_analysis_time"`
	SilenceThreshold     uint16 `json:"silence_threshold"`
	AfterGreetingSilence uint16 `json:"after_greeting_silence"`
	Greeting             uint16 `json:"greeting"`
	InitialSilence       uint16 `json:"initial_silence"`
	buildString          *string
}

type QueueCallbackSettings struct {
	Enabled bool  `json:"enabled"`
	Timeout int32 `json:"timeout"`
}

type QueueHook struct {
	Event      string   `json:"event"`
	SchemaId   uint32   `json:"schema_id"`
	Properties []string `json:"properties"`
}

/* TODO
Max wait - not hangup
Max wait time with no agent - offline + onbreak
Agent stickli
*/

// {"time_base_score": "system", "timeout_with_no_agents": "12", "discard_abandoned_after": "1000"}
type QueueInboundSettings struct {
	DiscardAbandonedAfter int    `json:"discard_abandoned_after"`
	TimeBaseScore         string `json:"time_base_score"` // ENUM queue, system
	MaxWaitWithNoAgent    int    `json:"timeout_with_no_agents"`
	//HangupOnRingingAgent bool   `json:"hangup_on_ringing_agent"`
	MaxCallPerAgent    int     `json:"max_call_per_agent"`
	AllowGreetingAgent bool    `json:"allow_greeting_agent"`
	MaxWaitTime        uint16  `json:"max_wait_time"`
	StickyAgent        bool    `json:"sticky_agent"`
	StickyAgentSec     uint16  `json:"sticky_agent_sec"` // def 30 sec
	AutoAnswerTone     *string `json:"auto_answer_tone"`
	ManualDistribution bool    `json:"manual_distribution"`
}

func QueueInboundSettingsFromBytes(data []byte) QueueInboundSettings {
	var settings QueueInboundSettings
	json.Unmarshal(data, &settings)
	return settings
}

func (amd *QueueAmdSettings) ToArgs() string {
	if amd.buildString == nil {
		tmp := make([]string, 0, 9)
		if amd.SilenceThreshold == 0 {
			amd.SilenceThreshold = 256
		}
		tmp = append(tmp, fmt.Sprintf("silence_threshold=%d", amd.SilenceThreshold))

		if amd.MaxWordLength == 0 {
			amd.MaxWordLength = 5000
		}
		tmp = append(tmp, fmt.Sprintf("maximum_word_length=%d", amd.MaxWordLength))

		if amd.MaxNumberOfWords == 0 {
			amd.MaxNumberOfWords = 3
		}
		tmp = append(tmp, fmt.Sprintf("maximum_number_of_words=%d", amd.MaxNumberOfWords))

		if amd.BetweenWordsSilence == 0 {
			amd.BetweenWordsSilence = 50
		}
		tmp = append(tmp, fmt.Sprintf("between_words_silence=%d", amd.BetweenWordsSilence))

		if amd.MinWordLength == 0 {
			amd.MinWordLength = 100
		}
		tmp = append(tmp, fmt.Sprintf("min_word_length=%d", amd.MinWordLength))

		if amd.TotalAnalysisTime == 0 {
			amd.TotalAnalysisTime = 5000
		}
		tmp = append(tmp, fmt.Sprintf("total_analysis_time=%d", amd.TotalAnalysisTime))

		if amd.AfterGreetingSilence == 0 {
			amd.AfterGreetingSilence = 800
		}
		tmp = append(tmp, fmt.Sprintf("after_greeting_silence=%d", amd.AfterGreetingSilence))

		if amd.Greeting == 0 {
			amd.Greeting = 1500
		}
		tmp = append(tmp, fmt.Sprintf("greeting=%d", amd.Greeting))

		if amd.InitialSilence == 0 {
			amd.InitialSilence = 2500
		}
		tmp = append(tmp, fmt.Sprintf("initial_silence=%d", amd.InitialSilence))

		if amd.AllowNotSure && amd.SilenceNotSure {
			tmp = append(tmp, "silence_notsure=1")
		}

		amd.buildString = new(string)
		*amd.buildString = strings.Join(tmp, " ")
	}

	return *amd.buildString
}

func (amd *QueueAmdSettings) AiTags() string {
	if len(amd.PositiveTags) == 0 {
		return "human"
	}

	return strings.Join(amd.PositiveTags, ",")
}
