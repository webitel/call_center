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

type test struct {
	Timestamp int64 `json:"timestamp" db:"timestamp"`
}

func (s *SqlMemberStore) SetAttemptOffering(attemptId int64, agentId *int, agentCallId, memberCallId *string) (int64, *model.AppError) {
	timestamp, err := s.GetMaster().SelectInt(`select cc_view_timestamp(x.last_state_change)::int8 as "timestamp"
from cc_attempt_offering(:AttemptId, :AgentId, :AgentCallId, :MemberCallId)
    as x (last_state_change timestamptz)
where x.last_state_change notnull `, map[string]interface{}{
		"AttemptId":    attemptId,
		"AgentId":      agentId,
		"AgentCallId":  agentCallId,
		"MemberCallId": memberCallId,
	})

	if err != nil {
		return 0, model.NewAppError("SqlMemberStore.SetAttemptOffering", "store.sql_member.set_attempt_offering.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", attemptId, err.Error()), http.StatusInternalServerError)
	}

	return timestamp, nil
}

func (s *SqlMemberStore) SetAttemptBridged(attemptId int64) (int64, *model.AppError) {
	timestamp, err := s.GetMaster().SelectInt(`select cc_view_timestamp(x.last_state_change)::int8 as "timestamp"
from cc_attempt_bridged(:AttemptId)
    as x (last_state_change timestamptz)
where x.last_state_change notnull `, map[string]interface{}{
		"AttemptId": attemptId,
	})

	if err != nil {
		return 0, model.NewAppError("SqlMemberStore.SetAttemptBridged", "store.sql_member.set_attempt_bridged.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", attemptId, err.Error()), http.StatusInternalServerError)
	}

	return timestamp, nil
}

func (s *SqlMemberStore) SetAttemptAbandoned(attemptId int64) (int64, *model.AppError) {
	timestamp, err := s.GetMaster().SelectInt(`select cc_view_timestamp(x.last_state_change)::int8 as "timestamp"
from cc_attempt_abandoned(:AttemptId)
    as x (last_state_change timestamptz)
where x.last_state_change notnull `, map[string]interface{}{
		"AttemptId": attemptId,
	})

	if err != nil {
		return 0, model.NewAppError("SqlMemberStore.SetAttemptBridged", "store.sql_member.set_attempt_bridged.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", attemptId, err.Error()), http.StatusInternalServerError)
	}

	return timestamp, nil
}

func (s *SqlMemberStore) SetAttemptMissedAgent(attemptId int64, agentHoldSec int) (int64, *model.AppError) {
	timestamp, err := s.GetMaster().SelectInt(`select cc_view_timestamp(x.last_state_change)::int8 as "timestamp"
from cc_attempt_missed_agent(:AttemptId, :AgentHoldSec)
    as x (last_state_change timestamptz)
where x.last_state_change notnull `, map[string]interface{}{
		"AttemptId":    attemptId,
		"AgentHoldSec": agentHoldSec,
	})

	if err != nil {
		return 0, model.NewAppError("SqlMemberStore.SetAttemptBridged", "store.sql_member.set_attempt_bridged.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", attemptId, err.Error()), http.StatusInternalServerError)
	}

	return timestamp, nil
}

func (s *SqlMemberStore) SetAttemptReporting(attemptId int64, deadlineSec int) (int64, *model.AppError) {
	timestamp, err := s.GetMaster().SelectInt(`with att as (
    update cc_member_attempt
    set timeout  = now() + (:DeadlineSec::varchar || ' sec')::interval,
        reporting_at = now(),
        state_str = :State,
		result = 'FIXME'
    where id = :Id
    returning agent_id, channel, state_str, reporting_at
)
update cc_agent_channel c
set state = att.state_str,
    joined_at = att.reporting_at
from att
where (att.agent_id, att.channel) = (c.agent_id, c.channel)
returning cc_view_timestamp(c.joined_at) as timestamp`, map[string]interface{}{
		"State":       model.ChannelStateReporting,
		"Id":          attemptId,
		"DeadlineSec": deadlineSec,
	})

	if err != nil {
		return 0, model.NewAppError("SqlMemberStore.SetAttemptReporting", "store.sql_member.set_attempt_reporting.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", attemptId, err.Error()), http.StatusInternalServerError)
	}

	return timestamp, nil
}

func (s *SqlMemberStore) SetAttemptMissed(id int64, holdSec, agentHoldTime int) (int64, *model.AppError) {
	timestamp, err := s.GetMaster().SelectInt(`select cc_view_timestamp(cc_attempt_leaving(:Id::int8, :HoldSec::int, 'MISSED', :State, :AgentHoldTime)) as timestamp`,
		map[string]interface{}{
			"State":         model.ChannelStateMissed,
			"Id":            id,
			"HoldSec":       holdSec,
			"AgentHoldTime": agentHoldTime,
		})

	if err != nil {
		return 0, model.NewAppError("SqlMemberStore.SetAttemptMissed", "store.sql_member.set_attempt_missed.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", id, err.Error()), http.StatusInternalServerError)
	}

	return timestamp, nil
}

func (s *SqlMemberStore) SetAttemptResult(id int64, result string, holdSec int, channelState string, agentHoldTime int) (int64, *model.AppError) {
	timestamp, err := s.GetMaster().SelectInt(`select cc_view_timestamp(cc_attempt_leaving(:Id::int8, :HoldSec::int, :Result::varchar, :State::varchar, :AgentHoldTime)) as timestamp`,
		map[string]interface{}{
			"Result":        result,
			"State":         channelState,
			"Id":            id,
			"HoldSec":       holdSec,
			"AgentHoldTime": agentHoldTime,
		})

	if err != nil {
		return 0, model.NewAppError("SqlMemberStore.SetAttemptMissed", "store.sql_member.set_attempt_missed.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", id, err.Error()), http.StatusInternalServerError)
	}

	return timestamp, nil
}

func (s *SqlMemberStore) GetTimeouts(nodeId string) ([]*model.AttemptTimeout, *model.AppError) {
	var attempts []*model.AttemptTimeout
	_, err := s.GetMaster().Select(&attempts, `select a.id, cc_view_timestamp(cc_attempt_leaving(a.id, cq.sec_between_retries, 'abandoned', 'waiting',0)) as timestamp,
       'waiting' as result
from cc_member_attempt a
    left join cc_queue cq on a.queue_id = cq.id
    left join cc_team ct on cq.team_id = ct.id
where a.timeout < now() and a.node_id = :NodeId`, map[string]interface{}{
		"NodeId": nodeId,
	})

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.GetTimeouts", "store.sql_member.get_timeouts.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}

	return attempts, nil
}

func (s *SqlMemberStore) Reporting(attemptId int64, status string) (*model.AttemptReportingResult, *model.AppError) {
	var result *model.AttemptReportingResult
	err := s.GetMaster().SelectOne(&result, `select *
from cc_attempt_end_reporting(:AttemptId::int8, :Status) as x (timestamp int8, channel varchar, agent_call_id varchar, agent_id int, agent_timeout int8)`, map[string]interface{}{
		"AttemptId": attemptId,
		"Status":    "success", //FIXME
	})

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.Reporting", "store.sql_member.reporting.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}

	return result, nil
}

func (s SqlMemberStore) SaveToHistory() ([]*model.HistoryAttempt, *model.AppError) {
	var res []*model.HistoryAttempt

	_, err := s.GetMaster().Select(&res, `with del as (
    delete
        from cc_member_attempt a
    where a.leaving_at notnull
    returning *
)
insert
into cc_member_attempt_history (id, queue_id, member_id, weight, resource_id, result,
                                agent_id, bucket_id, destination, display, description, list_communication_id,
                                joined_at, leaving_at, agent_call_id, member_call_id, offering_at, reporting_at,
                                bridged_at, created_at, channel)
select a.id, a.queue_id, a.member_id, a.weight, a.resource_id, a.result, a.agent_id, a.bucket_id, a.destination,
       a.display, a.description, a.list_communication_id, a.joined_at, a.leaving_at, a.agent_call_id, a.member_call_id,
       a.offering_at, a.reporting_at, a.bridged_at, a.created_at, a.channel
from del a
returning cc_member_attempt_history.id, cc_member_attempt_history.result`)

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.SaveToHistory", "store.sql_member.save_history.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}
	return res, nil
}
