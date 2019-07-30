package call_manager

import (
	"context"
	"fmt"
	"github.com/webitel/call_center/cluster"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq/rabbit"
	"github.com/webitel/call_center/utils"
	"testing"
	"time"
)

const (
	TEST_NODE_ID = "call-center-test"
)

func TestCallManager(t *testing.T) {
	t.Log("TestCallManager")

	cfg, _, _, err := utils.LoadConfig("")
	if err != nil {

	}

	mq := rabbit.NewRabbitMQ(cfg.MQSettings, TEST_NODE_ID)

	service, err := cluster.NewServiceDiscovery(TEST_NODE_ID, func() (bool, *model.AppError) {
		return true, nil
	})

	cm := NewCallManager(TEST_NODE_ID, service, mq)
	cm.Start()
	//testAsync(cm.(*CallManagerImpl), t)
	testCallError(cm, t)
	testCallAnswer(cm, t)
	testCallStates(cm, t)
	testCallHangup(cm, t)
	testCallHold(cm, t)
	testParentCall(cm, t)

	if cm.ActiveCalls() != 0 {
		t.Errorf("Call manager calls %v", cm.ActiveCalls())
	}

	cm.Stop()
	mq.Close()

}

func testAsync(cm *CallManagerImpl, t *testing.T) {
	cr := &model.CallRequest{
		Endpoints: []string{`loopback/sleep:100000\,park/default/inline`},
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

	api, _ := cm.pool.getByRoundRobin()

	ctx, cancel := context.WithCancel(context.Background())

	call := NewAsyncCall(ctx, cr, cm, api)

	go func() {
		time.Sleep(time.Second)
		cancel()
	}()

	select {
	case <-call.HangupChan():
		time.Sleep(time.Second)
		fmt.Println(">>>>>>>>>>> ", call.HangupCause())
		return
	}

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
		Endpoints: []string{`loopback/answer\,park/default/inline`},
		Variables: map[string]string{
			"cc_test_call_manager": "true",
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
		Endpoints: []string{`loopback/answer\,park/default/inline`},
		Variables: map[string]string{
			"cc_test_call_manager": "true",
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
		Endpoints: []string{`loopback/answer\,park/default/inline`},
		Variables: map[string]string{
			"cc_test_call_manager": "true",
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

func testCallHold(cm CallManager, t *testing.T) {
	t.Log("testCallHold")
	cr := &model.CallRequest{
		Endpoints: []string{`loopback/answer\,park/default/inline`},
		Variables: map[string]string{
			"cc_test_call_manager": "true",
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

	err := call.Hold()
	if err != nil {
		t.Errorf(err.Error())
	}

	err = call.Hangup(model.CALL_HANGUP_NO_ANSWER)
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

func testParentCall(cm CallManager, t *testing.T) {
	t.Log("testParentCall")

	ch := make(chan struct{})

	close(ch)
	<-ch

	cr := &model.CallRequest{
		Endpoints: []string{`loopback/answer\,park/default/inline`},
		Variables: map[string]string{
			"cc_test_call_manager": "true",
		},
		Applications: []*model.CallRequestApplication{
			{
				AppName: model.CALL_ANSWER_APPLICATION,
			},
			{
				AppName: model.CALL_SLEEP_APPLICATION,
				Args:    "50000",
			},
		},
	}
	call := cm.NewCall(cr)
	if call.Err() != nil {
		t.Errorf("call error: %s", call.Err().Error())
	}

	call2 := call.NewCall(cr)
	if call2.Err() != nil {
		t.Errorf("call error: %s", call2.Err().Error())
	}

	if err := call2.Bridge(call); err != nil {
		t.Errorf("call error: %s", err.Error())
	}

	go func() {
		time.Sleep(time.Millisecond * 100)

		call.Hangup(model.CALL_NORMAL_CLEARING)
		call2.Hangup(model.CALL_NORMAL_CLEARING)
	}()

	call.WaitForHangup()
	call2.WaitForHangup()

	if call.HangupCause() != model.CALL_NORMAL_CLEARING || call2.HangupCause() != model.CALL_NORMAL_CLEARING {
		t.Errorf("call error: bad hangup cause")
	}

	if call.BridgeAt() == 0 || call2.BridgeAt() == 0 {
		t.Errorf("call error: no bridge time")
	}
}
