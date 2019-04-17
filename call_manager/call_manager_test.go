package call_manager

import (
	"github.com/webitel/call_center/externalCommands"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq/rabbit"
	"github.com/webitel/call_center/utils"
	"testing"
)

func TestCallManager(t *testing.T) {
	t.Log("TestCallManager")

	cfg, _, _, err := utils.LoadConfig("")
	if err != nil {

	}

	mq := rabbit.NewRabbitMQ(cfg.MQSettings, "node-1")

	api := externalCommands.NewCallCommands(cfg.ExternalCommandsSettings)
	cm := NewCallManager("node-1", api, mq)
	cm.Start()

	testCallError(cm, t)
	testCallAnswer(cm, t)
	testCallStates(cm, t)
	testCallHangup(cm, t)

	if cm.ActiveCalls() != 0 {
		t.Errorf("Call manager calls %v", cm.ActiveCalls())
	}

	cm.Stop()
	mq.Close()
	api.Close()

}

func testCallError(cm CallManager, t *testing.T) {
	t.Log("testCallBusy")
	cr := &model.CallRequest{
		Endpoints: []string{"error/USER_BUSY"},
		Variables: map[string]string{
			"cc_test_call_manager": "true",
		},
		Applications: []*model.CallRequestApplication{
			{
				AppName: model.CALL_SLEEP_APPLICATION,
				Args:    "20000",
			},
		},
	}
	call := cm.NewCall(cr)
	if call.HangupCause() != model.CALL_HANGUP_USER_BUSY || call.Err() == nil {
		t.Errorf("Call hangup assert error: %s", call.HangupCause())
	}
}

func testCallAnswer(cm CallManager, t *testing.T) {
	t.Log("testCallAnswer")
	cr := &model.CallRequest{
		Endpoints: []string{"loopback/0"},
		Variables: map[string]string{
			model.CALL_DOMAIN_VARIABLE: "10.10.10.144",
			"cc_test_call_manager":     "true",
		},
		Applications: []*model.CallRequestApplication{
			{
				AppName: model.CALL_ANSWER_APPLICATION,
			},
			{
				AppName: model.CALL_HANGUP_APPLICATION,
				Args:    model.CALL_HANGUP_REJECTED,
			},
		},
	}
	call := cm.NewCall(cr)
	if call.Err() != nil {
		t.Errorf("call error: %s", call.Err().Error())
	}

	call.WaitForHangup()
	if call.Err() != nil {
		t.Errorf("call error: %s", call.Err().Error())
	}
	if call.HangupCause() != model.CALL_HANGUP_REJECTED {
		t.Errorf("assert hangup case error: %s", call.HangupCause())
	}
}

func testCallHangup(cm CallManager, t *testing.T) {
	t.Log("testCallHangup")
	cr := &model.CallRequest{
		Endpoints: []string{"loopback/0"},
		Variables: map[string]string{
			model.CALL_DOMAIN_VARIABLE: "10.10.10.144",
			"cc_test_call_manager":     "true",
		},
		Applications: []*model.CallRequestApplication{

			{
				AppName: "pre_answer",
			},
			{
				AppName: "sleep",
				Args:    "3000",
			},
		},
	}
	call := cm.NewCall(cr)
	if call.Err() != nil {
		t.Errorf("call error: %s", call.Err().Error())
	}
	err := call.Hangup(model.CALL_HANGUP_NO_ANSWER)
	if err != nil {
		t.Errorf(err.Error())
	}
	call.WaitForHangup()

	if err != nil {
		t.Errorf(err.Error())
	}
	if call.HangupCause() != model.CALL_HANGUP_NO_ANSWER {
		t.Errorf("assert hangup case error: %s", call.HangupCause())
	}
}

func testCallStates(cm CallManager, t *testing.T) {
	t.Log("testCallStates")
	cr := &model.CallRequest{
		Endpoints: []string{"loopback/0"},
		Variables: map[string]string{
			model.CALL_DOMAIN_VARIABLE: "10.10.10.144",
			"cc_test_call_manager":     "true",
		},
		Applications: []*model.CallRequestApplication{

			{
				AppName: "answer",
			},
			{
				AppName: "park",
			},
		},
	}
	call := cm.NewCall(cr)
	if call.Err() != nil {
		t.Errorf("call error: %s", call.Err().Error())
	}

	if call.GetState() != CALL_STATE_ACCEPT {
		t.Errorf("assert call state error: %v", call.GetState())
	}

	err := call.Hangup(model.CALL_HANGUP_NO_ANSWER)
	if err != nil {
		t.Errorf(err.Error())
	}
	call.WaitForHangup()
	if call.GetState() != CALL_STATE_HANGUP {
		t.Errorf("assert call state error: %v", call.GetState())
	}

	if err != nil {
		t.Errorf(err.Error())
	}
	if call.HangupCause() != model.CALL_HANGUP_NO_ANSWER {
		t.Errorf("assert hangup case error: %s", call.HangupCause())
	}
}
