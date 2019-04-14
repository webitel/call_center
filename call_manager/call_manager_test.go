package call_manager

import (
	"github.com/webitel/call_center/externalCommands/grpc"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq/rabbit"
	"testing"
)

func TestCallManager(t *testing.T) {
	t.Log("TestCallManager")

	apiS := model.ExternalCommandsSettings{
		Urls: []string{"10.10.10.200:50051"},
	}

	mqS := model.MQSettings{
		Url: model.NewString("amqp://webitel:webitel@10.10.10.200:5672?heartbeat=0"),
	}
	mq := rabbit.NewRabbitMQ(mqS, "node-1")

	api := grpc.NewCommands(apiS)
	cm := NewCallManager("node-1", api, mq)
	cm.Start()
	testCallError(cm, t)
	testCallAnswer(cm, t)
	testCallHangup(cm, t)
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
	if call.HangupCause() != model.CALL_HANGUP_USER_BUSY {
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
	if call.Error() != nil {
		t.Errorf("call error: %s", call.Error().Error())
	}
	call.WaitHangup()
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
	if call.Error() != nil {
		t.Errorf("call error: %s", call.Error().Error())
	}
	err := call.Hangup(model.CALL_HANGUP_NO_ANSWER)
	if err != nil {
		t.Errorf(err.Error())
	}
	call.WaitHangup()
	if call.HangupCause() != model.CALL_HANGUP_NO_ANSWER {
		t.Errorf("assert hangup case error: %s", call.HangupCause())
	}
}
