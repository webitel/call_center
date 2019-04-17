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

	err = am.SetOnline(agent)
	if err != nil {
		t.Errorf("Set agent login %s error: %s", agent.Id(), err.Error())
	}

	return agent
}

func testLogOut(t *testing.T, am AgentManager, agent AgentObject) {
	err := am.SetOffline(agent)

	if err != nil {
		t.Errorf("Set agent logout %s error: %s", agent.Id(), err.Error())
	}
}

func testCustomState(t *testing.T, am AgentManager, agent AgentObject) {
	err := am.SetAgentState(agent, "cc_test", 1)
	if err != nil {
		t.Errorf("Set agent test state %s error: %s", agent.Id(), err.Error())
	}

	time.Sleep(time.Second * 3)
}
