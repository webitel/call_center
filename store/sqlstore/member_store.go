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
			result.Err = model.NewAppError("SqlQueueStore.UnReserveMembers", "store.sql_member.get_active.app_error",
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
