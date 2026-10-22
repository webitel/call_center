package call_manager

import (
	"testing"

	"github.com/webitel/call_center/model"
)

func TestSetRecordings(t *testing.T) {
	cases := []struct {
		name      string
		all       bool
		mono      bool
		bridgeReq string
		stereo    string
	}{
		{name: "defaults", all: false, mono: false, bridgeReq: "true", stereo: "true"},
		{name: "record all mono", all: true, mono: true, bridgeReq: "false", stereo: "false"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			call := &CallImpl{id: "c1", callRequest: &model.CallRequest{Variables: map[string]string{}}}

			call.SetRecordings(1, tc.all, tc.mono)

			apps := call.callRequest.Applications
			if len(apps) != 1 || apps[0].AppName != "wbt_record_session" {
				t.Fatalf("applications = %+v, want one wbt_record_session", apps)
			}

			want := map[string]string{
				"RECORD_MIN_SEC":            "2",
				"recording_follow_transfer": "true",
				"RECORD_BRIDGE_REQ":         tc.bridgeReq,
				"media_bug_answer_req":      tc.bridgeReq,
				"RECORD_STEREO":             tc.stereo,
			}
			for k, v := range want {
				if got := call.callRequest.Variables[k]; got != v {
					t.Errorf("%s = %q, want %q", k, got, v)
				}
			}
		})
	}
}
