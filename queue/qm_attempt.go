package queue

import (
	"github.com/webitel/call_center/model"
)

func (queueManager *QueueManager) SetAttemptState(attemptId int64, state int) *model.AppError {
	res := <-queueManager.store.Member().SetAttemptState(attemptId, state)
	return res.Err
}

func (queueManager *QueueManager) SetBridged(a *Attempt, legAId, legBId *string) *model.AppError {
	res := <-queueManager.store.Member().SetBridged(a.Id(), model.GetMillis(), legAId, legBId)
	return res.Err
}

func (queueManager *QueueManager) SetAttemptSuccess(attempt *Attempt, cause string) *model.AppError {
	if res := <-queueManager.store.Member().SetAttemptSuccess(attempt.Id(), model.GetMillis(), cause, attempt.LogsData()); res.Err != nil {
		return res.Err
	}
	return nil
}

func (queueManager *QueueManager) SetAttemptError(attempt *Attempt, cause string) (bool, *model.AppError) {
	if res := <-queueManager.store.Member().SetAttemptStop(attempt.Id(), model.GetMillis(), 1, true, cause, attempt.LogsData()); res.Err != nil {
		return false, res.Err
	} else {
		return res.Data.(bool), nil
	}
}

func (queueManager *QueueManager) SetAttemptMinus(attempt *Attempt, cause string) (bool, *model.AppError) {
	if res := <-queueManager.store.Member().SetAttemptStop(attempt.Id(), model.GetMillis(), 0, false, cause, attempt.LogsData()); res.Err != nil {
		return false, res.Err
	} else {
		return res.Data.(bool), nil
	}
}

func (queueManager *QueueManager) SetAttemptStop(attempt *Attempt, cause string) (bool, *model.AppError) {
	if res := <-queueManager.store.Member().SetAttemptStop(attempt.Id(), model.GetMillis(), 1, false, cause, attempt.LogsData()); res.Err != nil {
		return false, res.Err
	} else {
		return res.Data.(bool), nil
	}
}
