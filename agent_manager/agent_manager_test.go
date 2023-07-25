package agent_manager

import (
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/store/sqlstore"
	"github.com/webitel/call_center/utils"
	"testing"
	"time"
)

func TestAgentCallManager(t *testing.T) {
	t.Log("AgentCallManager")
	cfg, _, _, err := utils.LoadConfig("")
	if err != nil {
		panic(err)
	}
	s := store.NewLayeredStore(sqlstore.NewSqlSupplier(cfg.SqlSettings))
	am := NewAgentManager("node-1", s)
	am.Start()
	agent := testLogin(t, am)
	testPause(t, am, agent)
	testCustomState(t, am, agent)
	testLogOut(t, am, agent)
	am.Stop()
}

func testLogin(t *testing.T, am AgentManager) AgentObject {
	t.Log("testLogin")
	agent, err := am.GetAgent(1, 0)
	if err != nil {
		t.Errorf("GetAgent error: %s", err.Error())
	}

	_, err = am.SetOnline(agent, false)
	if err != nil {
		t.Errorf("Set agent login %d error: %s", agent.Id(), err.Error())
	}

	return agent
}

func testLogOut(t *testing.T, am AgentManager, agent AgentObject) {
	err := am.SetOffline(agent)

	if err != nil {
		t.Errorf("Set agent logout %d error: %s", agent.Id(), err.Error())
	}
}

func testPause(t *testing.T, am AgentManager, agent AgentObject) {
	err := am.SetPause(agent, []byte(`{"img":"src/img.jpeg","code":"chat"}`), 0)
	if err != nil {
		t.Errorf("Set agent pause %d error: %s", agent.Id(), err.Error())
	}
}

func testCustomState(t *testing.T, am AgentManager, agent AgentObject) {
	err := am.SetAgentState(agent, "cc_test", 1)
	if err != nil {
		t.Errorf("Set agent test state %d error: %s", agent.Id(), err.Error())
	}

	time.Sleep(time.Second * 3)
}
