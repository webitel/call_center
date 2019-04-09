package queue

import "encoding/json"

type AttemptInfoCall struct {
	LegAUri       string  `json:"leg_a_uri"`
	LegBUri       string  `json:"leg_b_uri"`
	UseAmd        bool    `json:"use_amd"`
	UseRecordings bool    `json:"use_recordings"`
	Error         *string `json:"error"`
}

func (a *AttemptInfoCall) Data() []byte {
	data, _ := json.Marshal(a)
	return data
}
