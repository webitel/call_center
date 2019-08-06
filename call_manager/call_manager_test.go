package call_manager

import (
	"fmt"
	"github.com/webitel/call_center/cluster"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq/rabbit"
	"github.com/webitel/call_center/utils"
	"sync"
	"testing"
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

	testCallCancel(cm, t)
	testCallError(cm, t)
	testWaitForHangup(cm, t)
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
	call.Invite()

	for {
		select {
		case state := <-call.State():
			if state == CALL_STATE_HANGUP {
				if call.HangupCause() != model.CALL_HANGUP_USER_BUSY || call.Err() == nil {
					t.Errorf("Call %s hangup assert error: %s", call.Id(), call.HangupCause())
				}
				return
			}
		}
	}

}

func testWaitForHangup(cm CallManager, t *testing.T) {
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
	call.Invite()

	call.WaitForHangup()

	if call.Err() != nil {
		t.Errorf("Call %s error: %s", call.Id(), call.Err().Error())
	}

	if call.HangupCause() != model.CALL_HANGUP_REJECTED {
		t.Errorf("Call %s hangup assert error: %s", call.Id(), call.HangupCause())
	}
}

func testCallCancel(cm CallManager, t *testing.T) {
	t.Log("testCallAnswer")
	cr := &model.CallRequest{
		Endpoints: []string{`loopback/answer\,park/default/inline`},
		Variables: map[string]string{
			"cc_test_call_manager": "true",
		},
		Timeout: 5,
		Applications: []*model.CallRequestApplication{
			{
				AppName: model.CALL_ANSWER_APPLICATION,
			},
			{
				AppName: model.CALL_SLEEP_APPLICATION,
				Args:    "1000",
			},
			{
				AppName: model.CALL_HANGUP_APPLICATION,
				Args:    model.CALL_HANGUP_REJECTED,
			},
		},
	}
	call := cm.NewCall(cr)
	call.Invite()

	if call.Err() != nil {
		t.Errorf("call %s error: %s", call.Id(), call.Err().Error())
	}

	call.Hangup(model.CALL_HANGUP_USER_BUSY)
	for {
		select {
		case state := <-call.State():

			switch state {
			case CALL_STATE_ACCEPT:
				call.WaitForHangup()

			case CALL_STATE_HANGUP:
				//if call.Err() != nil {
				//	t.Errorf("call %s error: %s", call.Id(), call.Err().Error())
				//}
				if call.HangupCause() != model.CALL_HANGUP_USER_BUSY {
					t.Errorf("call %s assert hangup case error: %s", call.Id(), call.HangupCause())
				}

				return
			}
		case <-call.HangupChan():
			if call.HangupCause() != model.CALL_HANGUP_USER_BUSY {
				t.Errorf("call %s assert hangup case error: %s", call.Id(), call.HangupCause())
			}
			return
		}
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
	call.Invite()

	if call.Err() != nil {
		t.Errorf("call error: %s", call.Err().Error())
	}

	var answer bool

	for {
		select {
		case state := <-call.State():

			switch state {
			case CALL_STATE_ACCEPT:
				answer = true

			case CALL_STATE_HANGUP:
				if call.Err() != nil {
					t.Errorf("call error: %s", call.Err().Error())
				}
				if call.HangupCause() != model.CALL_HANGUP_REJECTED {
					t.Errorf("assert hangup case error: %s", call.HangupCause())
				}
				if !answer {
					t.Errorf("assert not answered")
				}
				return
			}
		}
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
				AppName: "answer",
			},
			{
				AppName: "sleep",
				Args:    "3000",
			},
		},
	}
	call := cm.NewCall(cr)
	call.Invite()

	if call.Err() != nil {
		t.Errorf("call error: %s", call.Err().Error())
	}

	for {
		select {
		case state := <-call.State():

			switch state {
			case CALL_STATE_ACCEPT:
				err := call.Hangup(model.CALL_HANGUP_REJECTED)
				if err != nil {
					t.Errorf("assert call %s  error: %s", call.Id(), err.Error())
				}

			case CALL_STATE_HANGUP:
				if call.HangupCause() != model.CALL_HANGUP_REJECTED {
					t.Errorf("assert call %s hangup case error: %s", call.Id(), call.HangupCause())
				}
				return
			}
		}
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
	if call.GetState() != CALL_STATE_NEW {
		t.Errorf("assert state init error")
	}
	call.Invite()

	var ring, accept bool

	for {
		select {
		case state := <-call.State():
			switch state {
			case CALL_STATE_RINGING:
				ring = true
			case CALL_STATE_ACCEPT:
				accept = true
			case CALL_STATE_PARK:
				err := call.Hangup(model.CALL_HANGUP_NO_ANSWER)
				if err != nil {
					t.Errorf(err.Error())
				}
			case CALL_STATE_HANGUP:
				if call.HangupCause() != model.CALL_HANGUP_NO_ANSWER {
					t.Errorf("assert hangup case error: %s", call.HangupCause())
				}

				if !ring || !accept {
					t.Errorf("assert states")
				}

				return
			default:
				fmt.Println(state)
			}
		}
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
	call.Invite()

	for {
		select {
		case state := <-call.State():
			switch state {
			case CALL_STATE_ACCEPT:
				err := call.Hold()
				if err != nil {
					t.Errorf(err.Error())
				}
				err = call.Hangup(model.CALL_HANGUP_NO_ANSWER)
				if err != nil {
					t.Errorf("assert call %s error: %s", call.Id(), err.Error())
				}

			case CALL_STATE_HANGUP:
				if call.HangupCause() != model.CALL_HANGUP_NO_ANSWER {
					t.Errorf("assert call %s hangup case error: %s", call.Id(), call.HangupCause())
				}
				return
			}
		}
	}
}

func testParentCall(cm CallManager, t *testing.T) {
	t.Log("testParentCall")

	cr := &model.CallRequest{
		Endpoints: []string{`loopback/answer\,park/default/inline`},
		Variables: map[string]string{
			"cc_test_call_manager": "true",
			"hangup_after_bridge":  "true",
		},
		Applications: []*model.CallRequestApplication{
			{
				AppName: model.CALL_ANSWER_APPLICATION,
			},

			{
				AppName: model.CALL_PARK_APPLICATION,
			},
		},
	}

	cr2 := &model.CallRequest{
		Endpoints: []string{`loopback/answer\,park/default/inline`},
		Variables: map[string]string{
			"cc_test_call_manager": "true",
			"hangup_after_bridge":  "true",
		},
		Applications: []*model.CallRequestApplication{
			{
				AppName: model.CALL_ANSWER_APPLICATION,
			},
			{
				AppName: model.CALL_SLEEP_APPLICATION,
				Args:    "100",
			},
			{
				AppName: model.CALL_PARK_APPLICATION,
			},
		},
	}

	call := cm.NewCall(cr)
	call2 := call.NewCall(cr2)

	//fmt.Printf("call %s & %s start\n", call.Id(), call2.Id())

	call.Invite()
	call2.Invite()

	wg := sync.WaitGroup{}
	wg.Add(2)

	ch := make(chan struct{})

	go func() {
		wg.Wait()
		//fmt.Printf("call %s & %s close\n", call.Id(), call2.Id())
		close(ch)
	}()

	for {
		select {
		case <-ch:
			if call.HangupCause() != model.CALL_HANGUP_NORMAL_CLEARING {
				t.Errorf("call1 %s error: bad hangup cause %s", call.Id(), call.HangupCause())
			}
			if call2.HangupCause() != model.CALL_HANGUP_NORMAL_CLEARING {
				t.Errorf("call2 %s error: bad hangup cause %s", call2.Id(), call2.HangupCause())
			}

			if call.BridgeAt() == 0 || call2.BridgeAt() == 0 {
				t.Errorf("call error: no bridge time")
			}

			return
		case state := <-call.State():
			switch state {

			case CALL_STATE_BRIDGE:
				err := call.Hangup(model.CALL_HANGUP_NORMAL_CLEARING)
				if err != nil {
					t.Error(err.Error())
					panic(call.Id())
				}

			case CALL_STATE_HANGUP:
				wg.Add(-1)
			}
		case state2 := <-call2.State():
			switch state2 {
			case CALL_STATE_PARK:
				if err := call2.Bridge(call); err != nil {
					t.Errorf("call %s error: %s", call2.Id(), err.Error())
					fmt.Println(err.Error())
				}
			case CALL_STATE_HANGUP:
				wg.Add(-1)
			}
		}
	}
}
