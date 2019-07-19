package sqlstore

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"net/http"
)

type SqlMemberStore struct {
	SqlStore
}

func NewSqlMemberStore(sqlStore SqlStore) store.MemberStore {
	us := &SqlMemberStore{sqlStore}
	return us
}

func (s *SqlMemberStore) CreateTableIfNotExists() {
}

func (s SqlMemberStore) ReserveMembersByNode(nodeId string) (int64, *model.AppError) {
	if i, err := s.GetMaster().SelectInt(`select s as count
			from cc_reserve_members_with_resources($1) s`, nodeId); err != nil {
		return 0, model.NewAppError("SqlMemberStore.ReserveMembers", "store.sql_member.reserve_member_resources.app_error",
			map[string]interface{}{"Error": err.Error()},
			err.Error(), http.StatusInternalServerError)
	} else {
		return i, nil
	}
}

func (s SqlMemberStore) UnReserveMembersByNode(nodeId, cause string) (int64, *model.AppError) {
	if i, err := s.GetMaster().SelectInt(`select s as count
			from cc_un_reserve_members_with_resources($1, $2) s`, nodeId, cause); err != nil {
		return 0, model.NewAppError("SqlMemberStore.UnReserveMembers", "store.sql_member.un_reserve_member_resources.app_error",
			map[string]interface{}{"Error": err.Error()}, err.Error(), http.StatusInternalServerError)
	} else {
		return i, nil
	}
}

func (s SqlMemberStore) GetActiveMembersAttempt(nodeId string) ([]*model.MemberAttempt, *model.AppError) {
	var members []*model.MemberAttempt
	if _, err := s.GetMaster().Select(&members, `select *
			from cc_set_active_members($1) s`, nodeId); err != nil {
		return nil, model.NewAppError("SqlMemberStore.GetActiveMembersAttempt", "store.sql_member.get_active.app_error",
			map[string]interface{}{"Error": err.Error()},
			err.Error(), http.StatusInternalServerError)
	} else {
		return members, nil
	}
}

func (s SqlMemberStore) SetAttemptState(id int64, state int) *model.AppError {
	if _, err := s.GetMaster().Exec(`update cc_member_attempt
			set state = :State
			where id = :Id`, map[string]interface{}{"Id": id, "State": state}); err != nil {
		return model.NewAppError("SqlMemberStore.SetAttemptState", "store.sql_member.set_attempt_state.app_error", nil,
			fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
	}

	return nil
}

func (s SqlMemberStore) SetAttemptFindAgent(id int64) *model.AppError {
	if _, err := s.GetMaster().Exec(`update cc_member_attempt
			set state = :State,
				agent_id = null
			where id = :Id and state != :CancelState`, map[string]interface{}{"Id": id, "State": model.MEMBER_STATE_FIND_AGENT, "CancelState": model.MEMBER_STATE_CANCEL}); err != nil {
		return model.NewAppError("SqlMemberStore.SetFindAgentState", "store.sql_member.set_attempt_state_find_agent.app_error", nil,
			fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
	}

	return nil
}

func (s SqlMemberStore) SetBridged(id, bridgedAt int64, legAId, legBId *string) *model.AppError {
	if _, err := s.GetMaster().Exec(`update cc_member_attempt
			set state = :State,
				bridged_at = :BridgedAt,
				leg_a_id = coalesce(leg_a_id, :LegAId),
				leg_b_id = coalesce(leg_b_id, :LegBId)
			where id = :Id and hangup_at = 0`, map[string]interface{}{"Id": id, "State": model.MEMBER_STATE_ACTIVE, "BridgedAt": bridgedAt,
		"LegAId": legAId, "LegBId": legBId}); err != nil {
		return model.NewAppError("SqlMemberStore.SettBridged", "store.sql_member.set_bridged.app_error", nil,
			fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
	}
	return nil
}

func (s SqlMemberStore) ActiveCount(queue_id int64) (int64, *model.AppError) {
	if i, err := s.GetMaster().SelectInt(`select count(*) as count
			from cc_member_attempt a where a.queue_id = $1 and a.hangup_at = 0`, queue_id); err != nil {
		return 0, model.NewAppError("SqlMemberStore.ActiveCount", "store.sql_member.active_count.app_error",
			map[string]interface{}{"Error": err.Error()},
			err.Error(), http.StatusInternalServerError)
	} else {
		return i, nil
	}
}

func (s SqlMemberStore) SetAttemptSuccess(attemptId, hangupAt int64, cause string, data []byte) *model.AppError {
	if _, err := s.GetMaster().Exec(`select cc_set_attempt_success(:AttemptId, :HangupAt, :Data, :Result);`,
		map[string]interface{}{"AttemptId": attemptId, "HangupAt": hangupAt, "Data": data, "Result": cause}); err != nil {
		return model.NewAppError("SqlMemberStore.SetAttemptSuccess", "store.sql_member.set_attempt_success.app_error", nil,
			fmt.Sprintf("Id=%v, %s", attemptId, err.Error()), http.StatusInternalServerError)
	}
	return nil
}

func (s SqlMemberStore) SetAttemptStop(attemptId, hangupAt int64, delta int, isErr bool, cause string, data []byte) (bool, *model.AppError) {
	var stopped bool
	if err := s.GetMaster().SelectOne(&stopped, `select cc_set_attempt_stop(:AttemptId, :Delta, :IsErr, :HangupAt, :Data, :Result);`,
		map[string]interface{}{"AttemptId": attemptId, "Delta": delta, "IsErr": isErr, "HangupAt": hangupAt, "Data": data, "Result": cause}); err != nil {
		return false, model.NewAppError("SqlMemberStore.SetAttemptStop", "store.sql_member.set_attempt_stop.app_error", nil,
			fmt.Sprintf("Id=%v, %s", attemptId, err.Error()), http.StatusInternalServerError)
	} else {
		return stopped, nil
	}
}

func (s SqlMemberStore) SetAttemptBarred(attemptId, hangupAt int64, cause string, data []byte) (bool, *model.AppError) {
	var stopped bool
	if err := s.GetMaster().SelectOne(&stopped, `select cc_set_attempt_barred(:AttemptId, :HangupAt, :Data, :Result);`,
		map[string]interface{}{"AttemptId": attemptId, "HangupAt": hangupAt, "Data": data, "Result": cause}); err != nil {
		return false, model.NewAppError("SqlMemberStore.SetAttemptBarred", "store.sql_member.set_attempt_barred.app_error", nil,
			fmt.Sprintf("Id=%v, %s", attemptId, err.Error()), http.StatusInternalServerError)
	} else {
		return stopped, nil
	}
}

func (s SqlMemberStore) SetAttemptAgentId(attemptId int64, agentId *int64) *model.AppError {
	if _, err := s.GetMaster().Exec(`update cc_member_attempt
			set agent_id = :AgentId
			where id = :Id`, map[string]interface{}{"Id": attemptId, "AgentId": agentId}); err != nil {
		return model.NewAppError("SqlMemberStore.SetAttemptAgentId", "store.sql_member.set_attempt_agent_id.app_error", nil,
			fmt.Sprintf("Id=%v, AgentId=%v %s", attemptId, agentId, err.Error()), http.StatusInternalServerError)
	}
	return nil
}

func (s SqlMemberStore) AddMemberToQueue(queueId int64, callId string, number string, name string, priority int) (int64, *model.AppError) {
	var attemptId int64

	if err := s.GetMaster().SelectOne(&attemptId, `select attempt_id
		from cc_add_to_queue(:QueueId, :CallId, :Number, :Name, :Priority) attempt_id`, map[string]interface{}{
		"QueueId": queueId, "CallId": callId, "Number": number, "Name": name, "Priority": priority,
	}); err != nil {
		return 0, model.NewAppError("SqlMemberStore.AddMemberToQueue", "store.sql_member.add_member_to_queue.app_error", nil,
			fmt.Sprintf("QueueId=%v, CallId=%v Number=%v %s", queueId, callId, number, err.Error()), http.StatusInternalServerError)
	}

	return attemptId, nil
}
