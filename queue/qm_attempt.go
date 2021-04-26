package queue

import (
	"github.com/webitel/call_center/model"
)

func (queueManager *QueueManager) SetFindAgentState(attemptId int64) *model.AppError {
	return queueManager.store.Member().SetAttemptFindAgent(attemptId)
}

func (queueManager *QueueManager) AnswerPredictAndFindAgent(attemptId int64) *model.AppError {
	return queueManager.store.Member().AnswerPredictAndFindAgent(attemptId)
}
