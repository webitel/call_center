package queue

import (
	"github.com/webitel/call_center/model"
)

func (queueManager *QueueManager) SetAttemptState(attemptId int64, state int) *model.AppError {
	return queueManager.store.Member().SetAttemptState(attemptId, state)
}

func (queueManager *QueueManager) SetBridged(a *Attempt, legAId, legBId *string) *model.AppError {
	return queueManager.store.Member().SetBridged(a.Id(), model.GetMillis(), legAId, legBId)
}

func (queueManager *QueueManager) SetAttemptSuccess(attempt *Attempt, cause string) *model.AppError {
	return queueManager.store.Member().SetAttemptSuccess(attempt.Id(), model.GetMillis(), cause, attempt.LogsData())
}

func (queueManager *QueueManager) SetAttemptError(attempt *Attempt, cause string) (bool, *model.AppError) {
	return queueManager.store.Member().SetAttemptStop(attempt.Id(), model.GetMillis(), 1, true, cause, attempt.LogsData())
}

func (queueManager *QueueManager) SetAttemptMinus(attempt *Attempt, cause string) (bool, *model.AppError) {
	return queueManager.store.Member().SetAttemptStop(attempt.Id(), model.GetMillis(), 0, false, cause, attempt.LogsData())
}

func (queueManager *QueueManager) SetAttemptStop(attempt *Attempt, cause string) (bool, *model.AppError) {
	return queueManager.store.Member().SetAttemptStop(attempt.Id(), model.GetMillis(), 1, false, cause, attempt.LogsData())
}

func (queueManager *QueueManager) SetAttemptBarred(attempt *Attempt) (bool, *model.AppError) {
	return queueManager.store.Member().SetAttemptBarred(attempt.Id(), model.GetMillis(), model.CALL_OUTGOING_CALL_BARRED, attempt.LogsData())
}
