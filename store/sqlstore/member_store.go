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

func (s *SqlMemberStore) SetAttemptOffering(attemptId int64, agentId *int, agentCallId *string) (int64, *model.AppError) {
	timestamp, err := s.GetMaster().SelectInt(`with offering as (
    update cc_member_attempt
    set state_str = :State,
        offering_at = coalesce(offering_at, now()),
        agent_id = case when agent_id isnull  and :AgentId::int notnull then :AgentId else agent_id end,
        agent_call_id = case when agent_call_id isnull  and :AgentCallId::varchar notnull then :AgentCallId else agent_call_id end
    where id = :Id
    returning state_str, offering_at, agent_id, channel
), ch as (
    update cc_agent_channel ch
    set state = offering.state_str,
        joined_at = now()
    from offering
    where (offering.agent_id, offering.channel) = (ch.agent_id, ch.channel)
)
select cc_view_timestamp(now()) as timestamp
from offering`, map[string]interface{}{
		"Id":          attemptId,
		"State":       model.ChannelStateOffering,
		"AgentId":     agentId,
		"AgentCallId": agentCallId,
	})

	if err != nil {
		return 0, model.NewAppError("SqlMemberStore.SetAttemptOffering", "store.sql_member.set_attempt_offering.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", attemptId, err.Error()), http.StatusInternalServerError)
	}

	return timestamp, nil
}

func (s *SqlMemberStore) SetAttemptReporting(attemptId int64, deadlineSec int) (int64, *model.AppError) {
	timestamp, err := s.GetMaster().SelectInt(`with att as (
    update cc_member_attempt
    set timeout  = now() + (:DeadlineSec::varchar || ' sec')::interval,
        reporting_at = now(),
        state_str = :State
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
	_, err := s.GetMaster().Select(&attempts, `select a.id, cc_view_timestamp(cc_attempt_leaving(a.id, cq.sec_between_retries, 'MISSED', 'waiting',0)) as timestamp,
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
from cc_attempt_end_reporting(:AttemptId::int8, :Status) as x (timestamp int8, channel varchar, agent_call_id varchar)`, map[string]interface{}{
		"AttemptId": attemptId,
		"Status":    status,
	})

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.Reporting", "store.sql_member.reporting.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}

	return result, nil
}
