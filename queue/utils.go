package queue

import "github.com/webitel/call_center/model"

func Assert(src interface{}) {
	if src == nil {
		panic("assert error")
	}
}

func agentHangupCause(bridged bool) string {
	if bridged {
		return model.CALL_HANGUP_NORMAL_CLEARING
	}

	return model.CALL_HANGUP_ORIGINATOR_CANCEL
}
