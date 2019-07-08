package queue

import "encoding/json"

type AttemptInfoCall struct {
	LegAUri       string  `json:"leg_a_uri"`
	LegBUri       string  `json:"leg_b_uri"`
	UseAmd        bool    `json:"use_amd"`
	UseRecordings bool    `json:"use_recordings"`
	Timeout       bool    `json:"timeout"`
	AmdResult     *string `json:"amd_result,omitempty"`
	AmdCause      *string `json:"amd_cause,omitempty"`
	Error         *string `json:"error,omitempty"`
}

func (a *AttemptInfoCall) Data() []byte {
	data, _ := json.Marshal(a)
	return data
}
