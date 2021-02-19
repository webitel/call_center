package queue

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"sync"
)

const (
	MAX_TEAM_CACHE        = 10000
	MAX_TEAM_EXPIRE_CACHE = 60 * 60 * 24
)

type teamManager struct {
	store store.Store
	cache utils.ObjectCache
	sync.RWMutex
	mq mq.MQ
}

type agentTeam struct {
	data        *model.Team
	teamManager *teamManager
}

func (at *agentTeam) Name() string {
	return at.data.Name
}

func (at *agentTeam) Id() int64 {
	return at.data.Id
}

func (at *agentTeam) CallTimeout() uint16 {
	return at.data.CallTimeout
}

func (at *agentTeam) MaxNoAnswer() uint16 {
	return at.data.MaxNoAnswer
}

func (at *agentTeam) WrapUpTime() uint16 {
	return at.data.WrapUpTime
}

func (at *agentTeam) NoAnswerDelayTime() uint16 {
	return at.data.NoAnswerDelayTime
}

func NewTeamManager(s store.Store, m mq.MQ) *teamManager {
	return &teamManager{
		store: s,
		mq:    m,
		cache: utils.NewLruWithParams(MAX_TEAM_CACHE, "team", MAX_TEAM_EXPIRE_CACHE, ""),
	}
}

func (tm *teamManager) GetTeam(id int, updatedAt int64) (*agentTeam, *model.AppError) {
	tm.Lock() //TODO
	defer tm.Unlock()

	var team *agentTeam
	var err *model.AppError

	if t, ok := tm.cache.Get(id); ok {
		team = t.(*agentTeam)
		if team.data.UpdatedAt == updatedAt {
			return team, nil
		}
	}

	data, err := tm.store.Team().Get(id)
	if err != nil {
		return nil, err
	}
	team = &agentTeam{
		data:        data,
		teamManager: tm,
	}

	tm.cache.AddWithDefaultExpires(id, team)
	wlog.Debug(fmt.Sprintf("team [%d] %v store to cache", team.Id(), team.Name()))
	return team, err
}
