package agent_manager

import (
	"testing"
)

func TestAgentCallManager(t *testing.T) {
	t.Log("AgentCallManager")
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
	err := am.SetOffline(agent, nil)
	if err != nil {
		t.Errorf("Set agent logout %d error: %s", agent.Id(), err.Error())
	}
}

func testPause(t *testing.T, am AgentManager, agent AgentObject) {
	v := `{"img":"src/img.jpeg","code":"chat"}`
	err := am.SetPause(agent, &v, nil, nil)
	if err != nil {
		t.Errorf("Set agent pause %d error: %s", agent.Id(), err.Error())
	}
}
