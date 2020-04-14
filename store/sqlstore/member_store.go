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
	if i, err := s.GetMaster().SelectNullInt(`call test_sp(null)`); err != nil {
		return 0, model.NewAppError("SqlMemberStore.ReserveMembers", "store.sql_member.reserve_member_resources.app_error",
			map[string]interface{}{"Error": err.Error()},
			err.Error(), http.StatusInternalServerError)
	} else {
		return i.Int64, nil
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
			where id = :Id and state != :CancelState and result isnull`, map[string]interface{}{"Id": id, "State": model.MEMBER_STATE_FIND_AGENT, "CancelState": model.MEMBER_STATE_CANCEL}); err != nil {
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

func (s SqlMemberStore) DistributeCallToQueue(node string, queueId int64, callId string, number string, name string, priority int) (*model.MemberAttempt, *model.AppError) {
	var attempt *model.MemberAttempt

	if err := s.GetMaster().SelectOne(&attempt, `select *
		from cc_distribute_inbound_call_to_queue(:Node, :QueueId, :CallId, :Number, :Name, :Priority) attempt_id`, map[string]interface{}{
		"QueueId": queueId, "CallId": callId, "Number": number, "Name": name, "Priority": priority,
		"Node": node,
	}); err != nil {
		return nil, model.NewAppError("SqlMemberStore.DistributeCallToQueue", "store.sql_member.distribute_call.app_error", nil,
			fmt.Sprintf("QueueId=%v, CallId=%v Number=%v %s", queueId, callId, number, err.Error()), http.StatusInternalServerError)
	}

	return attempt, nil
}

func (s SqlMemberStore) DistributeDirect(node string, memberId int64, communicationId, agentId int) (*model.MemberAttempt, *model.AppError) {
	var res *model.MemberAttempt
	err := s.GetMaster().SelectOne(&res, `select * from cc_distribute_direct_member_to_queue(:AppId, :MemberId, :CommunicationId, :AgentId)`,
		map[string]interface{}{
			"AppId":           node,
			"MemberId":        memberId,
			"AgentId":         agentId,
			"CommunicationId": communicationId,
		})

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.DistributeDirect", "store.sql_member.distribute_direct.app_error", nil,
			fmt.Sprintf("MemberId=%v, AgentId=%v %s", memberId, agentId, err.Error()), http.StatusInternalServerError)
	}

	return res, nil

}

func (s SqlMemberStore) SetAttemptResult(result *model.AttemptResult) *model.AppError {
	_, err := s.GetMaster().Exec(`with rem as (
    delete from cc_member_attempt a
      where a.id = :Id
      returning *
  )
  insert into cc_member_attempt_log(id, queue_id, state, member_id, weight, resource_id, bucket_id, created_at, node_id, leg_a_id, leg_b_id, hangup_at, bridged_at, result, originate_at, answered_at, agent_id)
  select rem.id, rem.queue_id, -1, rem.member_id, rem.weight, rem.resource_id, rem.bucket_id, rem.created_at, rem.node_id, :LegA, :LegB, :HangupAt, :BridgedAt, :Result, :OfferingAt, :AnsweredAt, :AgentId
  from rem `, map[string]interface{}{
		"Id":         result.Id,
		"State":      result.State,
		"OfferingAt": result.OfferingAt,
		"AnsweredAt": result.AnsweredAt,
		"BridgedAt":  result.BridgedAt,
		"HangupAt":   result.HangupAt,
		"AgentId":    result.AgentId,
		"Result":     result.Result,
		"LegA":       result.LegAId,
		"LegB":       result.LegBId,
	})

	if err != nil {
		return model.NewAppError("SqlMemberStore.SetAttemptResult", "store.sql_member.set_attempt_result.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", result.Id, err.Error()), http.StatusInternalServerError)
	}

	return nil
}

func (s SqlMemberStore) Reporting(attemptId int64, result string) *model.AppError {
	_, err := s.GetMaster().Exec(`select cc_reporting_attempt(:AttemptId::int8, :Result::varchar, null::int8)`, map[string]interface{}{
		"AttemptId": attemptId,
		"Result":    result,
	})

	if err != nil {
		return model.NewAppError("SqlMemberStore.Reporting", "store.sql_member.set_attempt_result.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", attemptId, err.Error()), http.StatusInternalServerError)
	}

	return nil
}

func (s SqlMemberStore) AttemptOfferingAgent(attemptId int64, display string, agentCallId, memberCallId *string) (*model.AttemptOfferingAgent, *model.AppError) {
	var res *model.AttemptOfferingAgent
	err := s.GetMaster().SelectOne(&res, `select *
    		from cc_attempt_offering(:AttemptId::int8, :Display::varchar, :AgentCall::varchar, :MemberCall::varchar)`, map[string]interface{}{
		"AttemptId":  attemptId,
		"Display":    display,
		"AgentCall":  agentCallId,
		"MemberCall": memberCallId,
	})

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.OfferingAttempt", "store.sql_member.set_attempt_offering.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", attemptId, err.Error()), http.StatusInternalServerError)
	}

	return res, nil
}

//cc_attempt_bridged( attempt_id_ int8, agent_call_id_ varchar, member_call_id_ varchar)
func (s SqlMemberStore) BridgedAttempt(attemptId int64, agentCallId, memberCallId *string) (int64, *model.AppError) {
	i, err := s.GetMaster().SelectInt(`select cc_attempt_bridged(:AttemptId::int8, :AgentCall::varchar, :MemberCall::varchar)`, map[string]interface{}{
		"AttemptId":  attemptId,
		"AgentCall":  agentCallId,
		"MemberCall": memberCallId,
	})

	if err != nil {
		return 0, model.NewAppError("SqlMemberStore.BridgedAttempt", "store.sql_member.set_attempt_bridge.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", attemptId, err.Error()), http.StatusInternalServerError)
	}

	return i, nil
}

//cc_attempt_reporting(attempt_id_ int8)
func (s SqlMemberStore) ReportingAttempt(attemptId int64) (int64, *model.AppError) {
	i, err := s.GetMaster().SelectInt(`select cc_attempt_reporting(:AttemptId::int8)`, map[string]interface{}{
		"AttemptId": attemptId,
	})

	if err != nil {
		return 0, model.NewAppError("SqlMemberStore.ReportingAttempt", "store.sql_member.set_attempt_reporting.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", attemptId, err.Error()), http.StatusInternalServerError)
	}

	return i, nil
}

func (s SqlMemberStore) LeavingAttempt(attemptId int64, holdSec int, result *string) *model.AppError {
	_, err := s.GetMaster().Exec(`select cc_attempt_leaving(:AttemptId::int8, :HoldSec::int, :Result::varchar)`, map[string]interface{}{
		"AttemptId": attemptId,
		"HoldSec":   holdSec,
		"Result":    result,
	})

	if err != nil {
		return model.NewAppError("SqlMemberStore.LeavingAttempt", "store.sql_member.set_attempt_leaving.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", attemptId, err.Error()), http.StatusInternalServerError)
	}

	return nil
}
