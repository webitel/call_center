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

func (queueManager *QueueManager) Originate(a *Attempt) (*model.AttemptOriginateInfo, *model.AppError) {
	if result := <-queueManager.store.Member().AttemptOriginate(a.Id(), a.MemberId(), a.CommunicationId()); result.Err != nil {
		return nil, result.Err
	} else {
		return result.Data.(*model.AttemptOriginateInfo), nil
	}
}

func (queueManager *QueueManager) SetMemberError(member *model.MemberAttempt, cause int, result string) {
	res := <-queueManager.store.Member().SetEndMemberAttempt(member.Id, model.MEMBER_STATE_END, model.GetMillis(), result)
	if res.Err != nil {
		panic(res.Err.Error())
	}
}

func (queueManager *QueueManager) StopAttempt(attemptId int64, delta, state int, hangupAt int64, cause string) (*int64, *model.AppError) {
	if result := <-queueManager.store.Member().StopAttempt(attemptId, delta, state, hangupAt, cause); result.Err != nil {
		return nil, result.Err
	} else if result.Data != nil {
		return model.NewInt64(result.Data.(int64)), nil
	} else {
		return nil, nil
	}
}

//TODO remove
func (queueManager *QueueManager) SetAttemptError(attempt *Attempt, cause int, result string) {
	res := <-queueManager.store.Member().SetEndMemberAttempt(attempt.member.Id, model.MEMBER_STATE_END, model.GetMillis(), result)
	if res.Err != nil {
		panic(res.Err)
	}
}
