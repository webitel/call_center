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
			result.Err = model.NewAppError("SqlQueueStore.ReserveMembers", "store.sql_member.reserve_member_resources.app_error",
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
			result.Err = model.NewAppError("SqlQueueStore.UnReserveMembers", "store.sql_member.un_reserve_member_resources.app_error",
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
			from set_active_members($1) s`, nodeId); err != nil {
			result.Err = model.NewAppError("SqlQueueStore.GetActiveMembersAttempt", "store.sql_member.get_active.app_error",
				map[string]interface{}{"Error": err.Error()},
				err.Error(), http.StatusInternalServerError)
		} else {
			result.Data = members
		}
	})
}

func (s SqlMemberStore) SetEndMemberAttempt(id int64, state int, hangupAt int64, cause string) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		if _, err := s.GetMaster().Exec(`update cc_member_attempt
			set state = :State,
    		hangup_at = :HangupAt,
    		result = :Result
			where id = :Id`, map[string]interface{}{"Id": id, "State": state, "HangupAt": hangupAt, "Result": cause}); err != nil {
			result.Err = model.NewAppError("SqlMemberStore.SetEndMemberAttempt", "store.sql_member.set_end.app_error", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
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
			where id = :Id`, map[string]interface{}{"Id": id, "State": model.MEMBER_STATE_ACTIVE, "BridgedAt": bridgedAt,
			"LegAId": legAId, "LegBId": legBId}); err != nil {
			result.Err = model.NewAppError("SqlMemberStore.SettBridged", "store.sql_member.set_bridged.app_error", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
		}
	})
}

func (s SqlMemberStore) StopAttempt(attemptId int64, delta, state int, hangupAt int64, cause string) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		if i, err := s.GetMaster().SelectNullInt(`select * from cc_stop_attempt(:AttemptId::bigint, :Delta::smallint, :State::smallint,
      			:HangupAt::bigint, :Cause::varchar(50))`,
			map[string]interface{}{"AttemptId": attemptId, "Delta": delta, "State": state,
				"HangupAt": hangupAt, "Cause": cause}); err != nil {
			result.Err = model.NewAppError("SqlMemberStore.StopAttempt", "store.sql_member.stop_attempt.app_error", nil,
				fmt.Sprintf("Attempt Id=%v, %s", attemptId, err.Error()), http.StatusInternalServerError)
		} else {
			if i.Valid {
				result.Data = i.Int64
			} else {
				result.Data = nil
			}
		}
	})
}

func (s SqlMemberStore) ActiveCount(queue_id int64) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		if i, err := s.GetMaster().SelectInt(`select count(*) as count
			from cc_member_attempt a where a.queue_id = $1 and a.hangup_at = 0`, queue_id); err != nil {
			result.Err = model.NewAppError("SqlQueueStore.ActiveCount", "store.sql_member.active_count.app_error",
				map[string]interface{}{"Error": err.Error()},
				err.Error(), http.StatusInternalServerError)
		} else {
			result.Data = i
		}
	})
}
