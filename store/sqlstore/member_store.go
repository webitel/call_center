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
	for _, db := range sqlStore.GetAllConns() {
		table := db.AddTableWithName(model.MemberAttempt{}, "cc_member_attempt").SetKeys(true, "Id")
		table.ColMap("Id").SetUnique(true)
		table.ColMap("CommunicationId")
		table.ColMap("QueueId")
		table.ColMap("QueueUpdatedAt")
		table.ColMap("State")
		table.ColMap("MemberId")
		table.ColMap("CreatedAt")
		table.ColMap("HangupAt")
		table.ColMap("BridgedAt")
		table.ColMap("ResourceId")
		table.ColMap("ResourceUpdatedAt")
		table.ColMap("Result")
	}
	return us
}

func (s SqlMemberStore) ReserveMembersByNode(nodeId string) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		if i, err := s.GetMaster().SelectInt(`select s as count
			from reserve_members_with_resources($1) s`, nodeId); err != nil {
			result.Err = model.NewAppError("SqlMemberStore.ReserveMembers", "store.sql_member.reserve_member_resources.app_error",
				map[string]interface{}{"Error": err.Error()},
				err.Error(), http.StatusInternalServerError)
		} else {
			result.Data = i
		}
	})
}

func (s SqlMemberStore) UnReserveMembersByNode(nodeId, cause string) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		if i, err := s.GetMaster().SelectInt(`select s as count
			from un_reserve_members_with_resources($1, $2) s`, nodeId, cause); err != nil {
			result.Err = model.NewAppError("SqlMemberStore.UnReserveMembers", "store.sql_member.un_reserve_member_resources.app_error",
				map[string]interface{}{"Error": err.Error()},
				err.Error(), http.StatusInternalServerError)
		} else {
			result.Data = i
		}
	})
}

func (s SqlMemberStore) GetActiveMembersAttempt(nodeId string) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		var members []*model.MemberAttempt
		if _, err := s.GetMaster().Select(&members, `select *
			from cc_set_active_members($1) s`, nodeId); err != nil {
			result.Err = model.NewAppError("SqlMemberStore.GetActiveMembersAttempt", "store.sql_member.get_active.app_error",
				map[string]interface{}{"Error": err.Error()},
				err.Error(), http.StatusInternalServerError)
		} else {
			result.Data = members
		}
	})
}

func (s SqlMemberStore) SetAttemptState(id int64, state int) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		if _, err := s.GetMaster().Exec(`update cc_member_attempt
			set state = :State
			where id = :Id`, map[string]interface{}{"Id": id, "State": state}); err != nil {
			result.Err = model.NewAppError("SqlMemberStore.SetAttemptState", "store.sql_member.set_attempt_state.app_error", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
		}
	})
}

func (s SqlMemberStore) SetBridged(id, bridgedAt int64, legAId, legBId *string) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		if _, err := s.GetMaster().Exec(`update cc_member_attempt
			set state = :State,
				bridged_at = :BridgedAt,
				leg_a_id = coalesce(leg_a_id, :LegAId),
				leg_b_id = coalesce(leg_b_id, :LegBId)
			where id = :Id and hangup_at = 0`, map[string]interface{}{"Id": id, "State": model.MEMBER_STATE_ACTIVE, "BridgedAt": bridgedAt,
			"LegAId": legAId, "LegBId": legBId}); err != nil {
			result.Err = model.NewAppError("SqlMemberStore.SettBridged", "store.sql_member.set_bridged.app_error", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
		}
	})
}

func (s SqlMemberStore) ActiveCount(queue_id int64) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		if i, err := s.GetMaster().SelectInt(`select count(*) as count
			from cc_member_attempt a where a.queue_id = $1 and a.hangup_at = 0`, queue_id); err != nil {
			result.Err = model.NewAppError("SqlMemberStore.ActiveCount", "store.sql_member.active_count.app_error",
				map[string]interface{}{"Error": err.Error()},
				err.Error(), http.StatusInternalServerError)
		} else {
			result.Data = i
		}
	})
}

func (s SqlMemberStore) SetAttemptSuccess(attemptId, hangupAt int64, cause string, data []byte) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		if _, err := s.GetMaster().Exec(`select cc_set_attempt_success(:AttemptId, :HangupAt, :Data, :Result);`,
			map[string]interface{}{"AttemptId": attemptId, "HangupAt": hangupAt, "Data": data, "Result": cause}); err != nil {
			result.Err = model.NewAppError("SqlMemberStore.SetAttemptSuccess", "store.sql_member.set_attempt_success.app_error", nil,
				fmt.Sprintf("Id=%v, %s", attemptId, err.Error()), http.StatusInternalServerError)
		}
	})
}

func (s SqlMemberStore) SetAttemptStop(attemptId, hangupAt int64, delta int, isErr bool, cause string, data []byte) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		var stopped bool
		if err := s.GetMaster().SelectOne(&stopped, `select cc_set_attempt_stop(:AttemptId, :Delta, :IsErr, :HangupAt, :Data, :Result);`,
			map[string]interface{}{"AttemptId": attemptId, "Delta": delta, "IsErr": isErr, "HangupAt": hangupAt, "Data": data, "Result": cause}); err != nil {
			result.Err = model.NewAppError("SqlMemberStore.SetAttemptStop", "store.sql_member.set_attempt_stop.app_error", nil,
				fmt.Sprintf("Id=%v, %s", attemptId, err.Error()), http.StatusInternalServerError)
		} else {
			result.Data = stopped
		}
	})
}

func (s SqlMemberStore) SetAttemptAgentId(attemptId int64, agentId *int64) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		if _, err := s.GetMaster().Exec(`update cc_member_attempt
			set agent_id = :AgentId
			where id = :Id`, map[string]interface{}{"Id": attemptId, "AgentId": agentId}); err != nil {
			result.Err = model.NewAppError("SqlMemberStore.SetAttemptAgentId", "store.sql_member.set_attempt_agent_id.app_error", nil,
				fmt.Sprintf("Id=%v, AgentId=%v %s", attemptId, agentId, err.Error()), http.StatusInternalServerError)
		}
	})
}
