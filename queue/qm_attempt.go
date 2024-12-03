package queue

import (
	"github.com/webitel/call_center/model"
)

func (qm *Manager) SetFindAgentState(attemptId int64) *model.AppError {
	return qm.store.Member().SetAttemptFindAgent(attemptId)
}

func (qm *Manager) AnswerPredictAndFindAgent(attemptId int64) *model.AppError {
	return qm.store.Member().AnswerPredictAndFindAgent(attemptId)
}
