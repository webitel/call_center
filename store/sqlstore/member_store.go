package sqlstore

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/lib/pq"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
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

func (s *SqlMemberStore) ReserveMembersByNode(nodeId string, enableOmnichannel bool) (int64, *model.AppError) {
	if i, err := s.GetMaster().SelectNullInt(`call call_center.cc_distribute(:DisableOmnichannel::bool)`, map[string]interface{}{
		"DisableOmnichannel": !enableOmnichannel,
	}); err != nil {
		return 0, model.NewAppError("SqlMemberStore.ReserveMembers", "store.sql_member.reserve_member_resources.app_error",
			map[string]interface{}{"Error": err.Error()},
			err.Error(), http.StatusInternalServerError)
	} else {
		return i.Int64, nil
	}
}

func (s *SqlMemberStore) UnReserveMembersByNode(nodeId, cause string) (int64, *model.AppError) {
	if i, err := s.GetMaster().SelectInt(`select s as count
			from call_center.cc_un_reserve_members_with_resources($1, $2) s`, nodeId, cause); err != nil {
		return 0, model.NewAppError("SqlMemberStore.UnReserveMembers", "store.sql_member.un_reserve_member_resources.app_error",
			map[string]interface{}{"Error": err.Error()}, err.Error(), http.StatusInternalServerError)
	} else {
		return i, nil
	}
}

func (s *SqlMemberStore) GetActiveMembersAttempt(nodeId string) ([]*model.MemberAttempt, *model.AppError) {
	var members []*model.MemberAttempt
	if _, err := s.GetMaster().Select(&members, `select *
			from call_center.cc_set_active_members($1) s`, nodeId); err != nil {
		return nil, model.NewAppError("SqlMemberStore.GetActiveMembersAttempt", "store.sql_member.get_active.app_error",
			map[string]interface{}{"Error": err.Error()},
			err.Error(), http.StatusInternalServerError)
	} else {
		return members, nil
	}
}

func (s *SqlMemberStore) SetAttemptState(id int64, state int) *model.AppError {
	if _, err := s.GetMaster().Exec(`update call_center.cc_member_attempt
			set state = :State
			where id = :Id`, map[string]interface{}{"Id": id, "State": state}); err != nil {
		return model.NewAppError("SqlMemberStore.SetAttemptState", "store.sql_member.set_attempt_state.app_error", nil,
			fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
	}

	return nil
}

func (s *SqlMemberStore) SetAttemptFindAgent(id int64) *model.AppError {
	if _, err := s.GetMaster().Exec(`update call_center.cc_member_attempt
			set state = :State,
				agent_id = null,
				team_id = null
			where id = :Id and state != :CancelState and result isnull`, map[string]interface{}{
		"Id":          id,
		"State":       model.MemberStateWaitAgent,
		"CancelState": model.MemberStateCancel,
	}); err != nil {
		return model.NewAppError("SqlMemberStore.SetFindAgentState", "store.sql_member.set_attempt_state_find_agent.app_error", nil,
			fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
	}

	return nil
}

func (s *SqlMemberStore) AnswerPredictAndFindAgent(id int64) *model.AppError {
	if _, err := s.GetMaster().Exec(`update call_center.cc_member_attempt
			set state = :State,
				agent_id = null,
				answered_at = now()
			where id = :Id and state != :CancelState and result isnull`, map[string]interface{}{
		"Id":          id,
		"State":       model.MemberStateWaitAgent,
		"CancelState": model.MemberStateCancel,
	}); err != nil {
		return model.NewAppError("SqlMemberStore.AnswerPredictAndFindAgent", "store.sql_member.set_attempt_answer_find_agent.app_error", nil,
			fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
	}

	return nil
}

func (s *SqlMemberStore) SetDistributeCancel(id int64, description string, nextDistributeSec uint32, stop bool, vars map[string]string) *model.AppError {
	_, err := s.GetMaster().Exec(`call call_center.cc_attempt_distribute_cancel(:Id::int8, :Desc::varchar, :NextSec::int4, :Stop::bool, :Vars::jsonb)`,
		map[string]interface{}{
			"Id":      id,
			"Desc":    description,
			"NextSec": nextDistributeSec,
			"Stop":    stop,
			"Vars":    nil,
		})

	if err != nil {
		return model.NewAppError("SqlMemberStore.SetDistributeCancel", "store.sql_member.set_distribute_cancel.app_error", nil,
			fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
	}

	return nil
}

func (s *SqlMemberStore) DistributeCallToQueue(node string, queueId int64, callId string, vars map[string]string, bucketId *int32, priority int, stickyAgentId *int) (*model.InboundCallQueue, *model.AppError) {
	var att *model.InboundCallQueue
	err := s.GetMaster().SelectOne(&att, `select *
from call_center.cc_distribute_inbound_call_to_queue(:AppId::varchar, :QueueId::int8, :CallId::varchar, :Variables::jsonb,
	:BucketId::int, :Priority::int, :StickyAgentId::int4)
as x (
    attempt_id int8,
    queue_id int,
    queue_updated_at int8,
    destination jsonb,
    variables jsonb,
    name varchar,
    team_updated_at int8,

    call_id varchar,
    call_state varchar,
    call_direction varchar,
    call_destination varchar,
    call_timestamp int8,
    call_app_id varchar,
    call_from_number varchar,
    call_from_name varchar,
    call_answered_at int8,
    call_bridged_at int8,
    call_created_at int8
);`, map[string]interface{}{
		"AppId":         node,
		"QueueId":       queueId,
		"CallId":        callId,
		"Variables":     model.MapToJson(vars),
		"BucketId":      bucketId,
		"Priority":      priority,
		"StickyAgentId": stickyAgentId,
	})

	if err != nil {
		switch e := err.(type) {
		case *pq.Error:
			if e.Code == "MAXWS" {
				return nil, model.ErrQueueMaxWaitSize
			}

		}

		return nil, model.NewAppError("SqlMemberStore.DistributeCallToQueue", "store.sql_member.distribute_call.app_error", nil,
			fmt.Sprintf("QueueId=%v, CallId=%v %s", queueId, callId, err.Error()), http.StatusInternalServerError)
	}

	return att, nil
}

func (s *SqlMemberStore) DistributeCallToAgent(node string, callId string, vars map[string]string, agentId int32, force bool, params *model.QueueDumpParams) (*model.InboundCallAgent, *model.AppError) {
	var att *model.InboundCallAgent

	err := s.GetMaster().SelectOne(&att, `select *
from call_center.cc_distribute_inbound_call_to_agent(:Node, :MemberCallId, :Variables, :AgentId, :Prams::jsonb)
as x (
    attempt_id int8,
    destination jsonb,
    variables jsonb,
    name varchar,
    team_id int,
    team_updated_at int8,
    agent_updated_at int8,

    call_id varchar,
    call_state varchar,
    call_direction varchar,
    call_destination varchar,
    call_timestamp int8,
    call_app_id varchar,
    call_from_number varchar,
    call_from_name varchar,
    call_answered_at int8,
    call_bridged_at int8,
    call_created_at int8
)
where :Force::bool or not exists(select 1 from call_center.cc_member_attempt a where a.agent_id = :AgentId and a.state != 'leaving' for update )`, map[string]interface{}{
		"Node":         node,
		"MemberCallId": callId,
		"Variables":    model.MapToJson(vars),
		"AgentId":      agentId,
		"Force":        force,
		"Prams":        params.ToJson(),
	})

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.DistributeCallToAgent", "store.sql_member.distribute_call_agent.app_error", nil,
			fmt.Sprintf("AgentId=%v, CallId=%v %s", agentId, callId, err.Error()), http.StatusInternalServerError)
	}

	return att, nil
}

func (s *SqlMemberStore) DistributeTaskToAgent(node string, domainId int64, agentId int32, dest []byte, vars map[string]string, force bool, params *model.QueueDumpParams) (*model.TaskToAgent, *model.AppError) {
	var att *model.TaskToAgent

	err := s.GetMaster().SelectOne(&att, `select *
from call_center.cc_distribute_task_to_agent(:Node, :DomainId, :AgentId, :Dest::jsonb, :Variables, :Params::jsonb)
as x (
    attempt_id int8,
    destination jsonb,
    variables jsonb,
    team_id int,
    team_updated_at int8,
    agent_updated_at int8
)
where :Force::bool or not exists(select 1 from call_center.cc_member_attempt a where a.agent_id = :AgentId and a.state != 'leaving' for update )`, map[string]interface{}{
		"Node":      node,
		"DomainId":  domainId,
		"Dest":      dest,
		"Variables": model.MapToJson(vars),
		"AgentId":   agentId,
		"Force":     force,
		"Params":    params.ToJson(),
	})

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.DistributeTaskToAgent", "store.sql_member.distribute_task_agent.app_error", nil,
			fmt.Sprintf("AgentId=%v %s", agentId, err.Error()), http.StatusInternalServerError)
	}

	return att, nil
}

func (s *SqlMemberStore) DistributeCallToQueueCancel(id int64) *model.AppError {
	_, err := s.GetMaster().Exec(`update call_center.cc_member_attempt
set result = 'cancel',
    state = 'leaving',
    leaving_at = now()
where id = :Id`, map[string]interface{}{
		"Id": id,
	})

	if err != nil {

		return model.NewAppError("SqlMemberStore.DistributeCallToQueue2Cancel", "store.sql_member.distribute_call_cancel.app_error", nil,
			fmt.Sprintf("Id=%v %s", id, err.Error()), http.StatusInternalServerError)
	}

	return nil
}

func (s *SqlMemberStore) DistributeChatToQueue(node string, queueId int64, convId string, vars map[string]string, bucketId *int32, priority int, stickyAgentId *int) (*model.InboundChatQueue, *model.AppError) {
	var attempt *model.InboundChatQueue

	var v *string
	if vars != nil {
		v = new(string)
		*v = model.MapToJson(vars)
	}

	if err := s.GetMaster().SelectOne(&attempt, `select *
		from call_center.cc_distribute_inbound_chat_to_queue(:AppId::varchar, :QueueId::int8, :ConvId::varchar, :Variables::jsonb,
	:BucketId::int, :Priority::int, :StickyAgentId::int) 
as x (
    attempt_id int8,
    queue_id int,
    queue_updated_at int8,
    destination jsonb,
    variables jsonb,
    name varchar,
    team_updated_at int8,

    conversation_id varchar,
    conversation_created_at int8
);`,
		map[string]interface{}{
			"AppId":         node,
			"QueueId":       queueId,
			"ConvId":        convId,
			"Variables":     v,
			"BucketId":      bucketId,
			"Priority":      priority,
			"StickyAgentId": stickyAgentId,
		}); err != nil {

		switch e := err.(type) {
		case *pq.Error:
			if e.Code == "MAXWS" {
				return nil, model.ErrQueueMaxWaitSize
			}

		}

		return nil, model.NewAppError("SqlMemberStore.DistributeChatToQueue", "store.sql_member.distribute_chat.app_error", nil,
			fmt.Sprintf("QueueId=%v, Id=%v %s", queueId, convId, err.Error()), http.StatusInternalServerError)
	}

	return attempt, nil
}

func (s *SqlMemberStore) DistributeDirect(node string, memberId int64, communicationId, agentId int) (*model.MemberAttempt, *model.AppError) {
	var res *model.MemberAttempt
	err := s.GetMaster().SelectOne(&res, `select * from call_center.cc_distribute_direct_member_to_queue(:AppId, :MemberId, :CommunicationId, :AgentId)`,
		map[string]interface{}{
			"AppId":           node,
			"MemberId":        memberId,
			"AgentId":         agentId,
			"CommunicationId": communicationId,
		})

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.DistributeDirect", "store.sql_member.distribute_direct.app_error", nil,
			fmt.Sprintf("MemberId=%v, AgentId=%v %s", memberId, agentId, err.Error()), extractCodeFromErr(err))
	}

	return res, nil

}

func (s *SqlMemberStore) SetAttemptOffering(attemptId int64, agentId *int, agentCallId, memberCallId *string, destination, display *string) (int64, *model.AppError) {
	timestamp, err := s.GetMaster().SelectInt(`select call_center.cc_view_timestamp(x.last_state_change)::int8 as "timestamp"
from call_center.cc_attempt_offering(:AttemptId::int8, :AgentId::int4, :AgentCallId::varchar, :MemberCallId::varchar, :Dest::varchar, :Displ::varchar)
    as x (last_state_change timestamptz)
where x.last_state_change notnull `, map[string]interface{}{
		"AttemptId":    attemptId,
		"AgentId":      agentId,
		"AgentCallId":  agentCallId,
		"MemberCallId": memberCallId,
		"Dest":         destination,
		"Displ":        display,
	})

	if err != nil {
		return 0, model.NewAppError("SqlMemberStore.SetAttemptOffering", "store.sql_member.set_attempt_offering.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", attemptId, err.Error()), http.StatusInternalServerError)
	}

	return timestamp, nil
}

func (s *SqlMemberStore) SetAttemptBridged(attemptId int64) (int64, *model.AppError) {
	timestamp, err := s.GetMaster().SelectInt(`select call_center.cc_view_timestamp(x.last_state_change)::int8 as "timestamp"
from call_center.cc_attempt_bridged(:AttemptId)
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

func (s *SqlMemberStore) SetAttemptAbandoned(attemptId int64) (*model.AttemptLeaving, *model.AppError) {
	var res *model.AttemptLeaving
	err := s.GetMaster().SelectOne(&res, `select call_center.cc_view_timestamp(x.last_state_change)::int8 as "timestamp", x.member_stop_cause, x.result
from call_center.cc_attempt_abandoned(:AttemptId)
    as x (last_state_change timestamptz, member_stop_cause varchar, result varchar)
where x.last_state_change notnull `, map[string]interface{}{
		"AttemptId": attemptId,
	})

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.SetAttemptAbandoned", "store.sql_member.set_attempt_abandoned.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", attemptId, err.Error()), http.StatusInternalServerError)
	}

	return res, nil
}

func mapToJson(m map[string]string) *string {
	if m == nil {
		return nil
	}

	if data, err := json.Marshal(m); err == nil {
		return model.NewString(string(data))
	}

	return nil
}

func (s *SqlMemberStore) SetAttemptAbandonedWithParams(attemptId int64, maxAttempts uint, sleep uint64, vars map[string]string,
	perNum bool, excludeNum bool, redial bool, desc *string, stickyAgentId *int32) (*model.AttemptLeaving, *model.AppError) {
	var res *model.AttemptLeaving
	err := s.GetMaster().SelectOne(&res, `select call_center.cc_view_timestamp(x.last_state_change)::int8 as "timestamp", x.member_stop_cause, x.result
from call_center.cc_attempt_abandoned(:AttemptId, :MaxAttempts, :Sleep, :Vars::jsonb, :PerNum::bool, :ExcludeNum::bool, :Redial::bool, :Desc::varchar, :StickyAgentId::int)
    as x (last_state_change timestamptz, member_stop_cause varchar, result varchar)
where x.last_state_change notnull `, map[string]interface{}{
		"AttemptId":     attemptId,
		"MaxAttempts":   maxAttempts,
		"Sleep":         sleep,
		"Vars":          mapToJson(vars),
		"PerNum":        perNum,
		"ExcludeNum":    excludeNum,
		"Redial":        redial,
		"Desc":          desc,
		"StickyAgentId": stickyAgentId,
	})

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.SetAttemptAbandonedWithParams", "store.sql_member.set_attempt_abandoned.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", attemptId, err.Error()), http.StatusInternalServerError)
	}

	return res, nil
}

func (s *SqlMemberStore) SetAttemptMissedAgent(attemptId int64, agentHoldSec int) (*model.MissedAgent, *model.AppError) {
	var res *model.MissedAgent
	err := s.GetMaster().SelectOne(&res, `select call_center.cc_view_timestamp(x.last_state_change)::int8 as "timestamp", no_answers
from call_center.cc_attempt_missed_agent(:AttemptId, :AgentHoldSec)
    as x (last_state_change timestamptz, no_answers int)
where x.last_state_change notnull `, map[string]interface{}{
		"AttemptId":    attemptId,
		"AgentHoldSec": agentHoldSec,
	})

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.SetAttemptMissedAgent", "store.sql_member.set_attempt_missed_agent.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", attemptId, err.Error()), http.StatusInternalServerError)
	}

	return res, nil
}

func (s *SqlMemberStore) SetAttemptWaitingAgent(attemptId int64, agentHoldSec int) *model.AppError {
	_, err := s.GetMaster().SelectNullInt(`select 1 as ok
from call_center.cc_attempt_waiting_agent(:AttemptId, :AgentHoldSec)
    as x (last_state_change timestamptz, no_answers int)
where x.last_state_change notnull `, map[string]interface{}{
		"AttemptId":    attemptId,
		"AgentHoldSec": agentHoldSec,
	})

	if err != nil {
		return model.NewAppError("SqlMemberStore.SetAttemptWaitingAgent", "store.sql_member.set_attempt_waiting_agent.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", attemptId, err.Error()), http.StatusInternalServerError)
	}

	return nil
}

func (s *SqlMemberStore) SetAttemptReporting(attemptId int64, deadlineSec uint32) (int64, *model.AppError) {
	timestamp, err := s.GetMaster().SelectInt(`with att as (
    update call_center.cc_member_attempt
    set timeout  = case when :DeadlineSec::int > 0 then  now() + (:DeadlineSec::int || ' sec')::interval end,
        leaving_at = now(),
	    last_state_change = now(),
        state = case when state <> 'leaving' then :State else state end
    where id = :Id
    returning agent_id, channel, state, leaving_at
)
update call_center.cc_agent_channel c
set state = att.state,
    joined_at = att.leaving_at
from att
where (att.agent_id, att.channel) = (c.agent_id, c.channel)
returning call_center.cc_view_timestamp(c.joined_at) as timestamp`, map[string]interface{}{
		"State":       model.ChannelStateProcessing,
		"Id":          attemptId,
		"DeadlineSec": deadlineSec,
	})

	if err != nil {
		return 0, model.NewAppError("SqlMemberStore.SetAttemptReporting", "store.sql_member.set_attempt_reporting.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", attemptId, err.Error()), http.StatusInternalServerError)
	}

	return timestamp, nil
}

// RenewalProcessing fixme queue_id
func (s *SqlMemberStore) RenewalProcessing(domainId, attId int64, renewalSec uint32) (*model.RenewalProcessing, *model.AppError) {
	var res *model.RenewalProcessing
	err := s.GetMaster().SelectOne(&res, `update call_center.cc_member_attempt a
 set timeout = now() + (:Renewal::int || ' sec')::interval
from call_center.cc_member_attempt a2
    inner join call_center.cc_agent ca on ca.id = a2.agent_id
    left join call_center.cc_queue cq on cq.id = a2.queue_id
where a2.id = :Id::int8
	and a2.id = a.id
	and (cq.id isnull or cq.processing_renewal_sec > 0)
    and ca.domain_id = :DomainId::int8
	and a2.state = 'processing'
returning
    a.id attempt_id,
	coalesce(a.queue_id,0) as queue_id,
    call_center.cc_view_timestamp(a.timeout) timeout,
    call_center.cc_view_timestamp(now()) "timestamp",
	coalesce(cq.processing_renewal_sec, (:Renewal::int / 2)::int) as renewal_sec,
    a.channel,
    ca.user_id,
    ca.domain_id`, map[string]interface{}{
		"DomainId": domainId,
		"Id":       attId,
		"Renewal":  renewalSec,
	})

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.RenewalProcessing", "store.sql_member.set_attempt_renewal.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", attId, err.Error()), extractCodeFromErr(err))
	}

	return res, nil
}

func (s *SqlMemberStore) SetAttemptMissed(id int64, agentHoldTime int, maxAttempts uint, waitBetween uint64, perNum bool) (*model.MissedAgent, *model.AppError) {
	var missed *model.MissedAgent
	err := s.GetMaster().SelectOne(&missed, `select call_center.cc_view_timestamp(x.last_state_change)::int8 as "timestamp", no_answers, member_stop_cause 
		from call_center.cc_attempt_leaving(:Id::int8, 'missed', :State, :AgentHoldTime, null::jsonb, :MaxAttempts::int, :WaitBetween::int, :PerNum::bool) 
		as x (last_state_change timestamptz, no_answers int, member_stop_cause varchar)`,
		map[string]interface{}{
			"State":         model.ChannelStateMissed,
			"Id":            id,
			"AgentHoldTime": agentHoldTime,
			"MaxAttempts":   maxAttempts,
			"WaitBetween":   waitBetween,
			"PerNum":        perNum,
		})

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.SetAttemptMissed", "store.sql_member.set_attempt_missed.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", id, err.Error()), http.StatusInternalServerError)
	}

	return missed, nil
}

func (s *SqlMemberStore) CancelAgentAttempt(id int64, agentHoldTime int) (*model.MissedAgent, *model.AppError) {
	var missed *model.MissedAgent
	err := s.GetMaster().SelectOne(&missed, `select call_center.cc_view_timestamp(x.last_state_change)::int8 as "timestamp", no_answers
from call_center.cc_attempt_agent_cancel(:AttemptId::int8, :Result::varchar, :AgentState::varchar, :AgentHoldSec::int4)
    as x (last_state_change timestamptz, no_answers int)
where x.last_state_change notnull `,
		map[string]interface{}{
			"AttemptId":    id,
			"Result":       model.ChannelStateMissed,
			"AgentState":   model.ChannelStateMissed,
			"AgentHoldSec": agentHoldTime,
		})

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.CancelAgentAttempt", "store.sql_member.set_attempt_agent_cancel.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", id, err.Error()), http.StatusInternalServerError)
	}

	return missed, nil
}

func (s *SqlMemberStore) SetBarred(id int64) *model.AppError {
	_, err := s.GetMaster().Exec(`with u as (
    update call_center.cc_member_attempt
        set leaving_at = now(),
            result = 'barred',
            state = 'leaving'
    where id = :AttemptId
    returning member_id, result
)
update call_center.cc_member m
set stop_at = now(),
    stop_cause = u.result
from u
where m.id = u.member_id`, map[string]interface{}{
		"AttemptId": id,
	})

	if err != nil {
		return model.NewAppError("SqlMemberStore.SetBarred", "store.sql_member.set_attempt_barred.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", id, err.Error()), http.StatusInternalServerError)
	}

	return nil
}

// fixme
func (s *SqlMemberStore) SetAttemptResult(id int64, result string, channelState string, agentHoldTime int, vars map[string]string,
	maxAttempts uint, waitBetween uint64, perNum bool, desc *string, stickyAgentId *int32) (*model.MissedAgent, *model.AppError) {
	var missed *model.MissedAgent
	err := s.GetMaster().SelectOne(&missed, `select call_center.cc_view_timestamp(x.last_state_change)::int8 as "timestamp", no_answers,  member_stop_cause
		from call_center.cc_attempt_leaving(:Id::int8, :Result::varchar, :State, :AgentHoldTime, :Vars::jsonb, :MaxAttempts::int, :WaitBetween::int, 
			:PerNum::bool, :Desc::varchar, :StickyAgentId::int) 
		as x (last_state_change timestamptz, no_answers int, member_stop_cause varchar)`,
		map[string]interface{}{
			"Result":        result,
			"State":         channelState,
			"Id":            id,
			"AgentHoldTime": agentHoldTime,
			"Vars":          mapToJson(vars),
			"MaxAttempts":   maxAttempts,
			"WaitBetween":   waitBetween,
			"PerNum":        perNum,
			"Desc":          desc,
			"StickyAgentId": stickyAgentId,
		})

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.SetAttemptResult", "store.sql_member.set_attempt_result.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", id, err.Error()), http.StatusInternalServerError)
	}

	return missed, nil
}

func (s *SqlMemberStore) GetTimeouts(nodeId string) ([]*model.AttemptReportingTimeout, *model.AppError) {
	var attempts []*model.AttemptReportingTimeout
	_, err := s.GetMaster().Select(&attempts, `select
       a.id attempt_id,
       call_center.cc_view_timestamp(call_center.cc_attempt_timeout(a.id, 'waiting', 0, coalesce((cq.payload->>'max_attempts')::int, 0), 
			coalesce((cq.payload->>'per_numbers')::bool, false), cq.after_schema_id notnull)) as timestamp,
       a.agent_id,
       (ag.updated_at - extract(epoch from u.updated_at))::int8 agent_updated_at,
       ag.user_id,
       ag.domain_id,
       a.channel,
	   cq.after_schema_id as after_schema_id
from call_center.cc_member_attempt a
    inner join call_center.cc_agent ag on ag.id = a.agent_id
    inner join directory.wbt_user u on u.id = ag.user_id
    left join call_center.cc_queue cq on a.queue_id = cq.id
where a.timeout < now() and a.node_id = :NodeId and not a.schema_processing is true `, map[string]interface{}{
		"NodeId": nodeId,
	})

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.GetTimeouts", "store.sql_member.get_timeouts.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}

	return attempts, nil
}

func (s *SqlMemberStore) SetTimeoutError(id int64) *model.AppError {
	_, err := s.GetMaster().Exec(`update call_center.cc_member_attempt
set schema_processing = false,
    result = 'timeout error'
where id = :Id;`, map[string]interface{}{
		"Id": id,
	})

	if err != nil {
		return model.NewAppError("SqlMemberStore.SetTimeoutError", "store.sql_member.set_timeouts.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}

	return nil
}

func (s *SqlMemberStore) CallbackReporting(attemptId int64, callback *model.AttemptCallback, maxAttempts uint, waitBetween uint64, perNum bool) (*model.AttemptReportingResult, *model.AppError) {
	var result *model.AttemptReportingResult
	err := s.GetMaster().SelectOne(&result, `select *
from call_center.cc_attempt_end_reporting(:AttemptId::int8, :Status::varchar, :Description::varchar, :ExpireAt::timestamptz, 
	coalesce(:NextCallAt::timestamptz, (:WaitBetweenReq::int || ' sec')::interval + now() ), :StickyAgentId::int, :Vars::jsonb, :MaxAttempts::int, :WaitBetween::int, :ExcludeDest::bool, :PerNum::bool) as
x (timestamp int8, channel varchar, queue_id int, agent_call_id varchar, agent_id int, user_id int8, domain_id int8, agent_timeout int8, member_stop_cause varchar, member_id int8)
where x.channel notnull`, map[string]interface{}{
		"AttemptId":      attemptId,
		"Status":         callback.Status,
		"Description":    callback.Description,
		"ExpireAt":       callback.ExpireAt,
		"NextCallAt":     model.UtcTime(callback.NextCallAt),
		"WaitBetweenReq": callback.WaitBetweenRetries,
		"StickyAgentId":  callback.StickyAgentId,
		"MaxAttempts":    maxAttempts,
		"WaitBetween":    waitBetween,
		"ExcludeDest":    callback.ExcludeCurrentCommunication,
		"PerNum":         perNum,
		"Vars":           callback.JsonVariables(),
	})

	if err != nil {
		code := extractCodeFromErr(err)
		if code == http.StatusNotFound {
			return nil, model.NewAppError("SqlMemberStore.Reporting", "store.sql_member.reporting.not_found", nil,
				"too many reporting function calls", code)
		} else {
			return nil, model.NewAppError("SqlMemberStore.Reporting", "store.sql_member.reporting.app_error", nil,
				err.Error(), code)
		}

	}

	if result.MemberId != nil && len(callback.AddCommunications) != 0 {
		err = s.addCommunications(*result.MemberId, callback.AddCommunications)
		if err != nil {
			return nil, model.NewAppError("SqlMemberStore.Reporting", "store.sql_member.reporting.add_comm", nil,
				err.Error(), 500)
		}
	}

	return result, nil
}

func (s *SqlMemberStore) SchemaResult(attemptId int64, callback *model.AttemptCallback, maxAttempts uint, waitBetween uint64, perNum bool) (*model.AttemptLeaving, *model.AppError) {
	var result *model.AttemptLeaving
	err := s.GetMaster().SelectOne(&result, `select call_center.cc_view_timestamp(x.last_state_change)::int8 as "timestamp", x.member_stop_cause, x.result
from call_center.cc_attempt_schema_result(:AttemptId::int8, :Status::varchar, :Description::varchar, :ExpireAt::timestamptz, 
	:NextCallAt::timestamptz, :StickyAgentId::int, :Vars::jsonb, :MaxAttempts::int, :WaitBetween::int, :ExcludeDest::bool, :PerNum::bool)
	as x (last_state_change timestamptz, member_stop_cause varchar, result varchar)
where x.last_state_change notnull`, map[string]interface{}{
		"AttemptId":     attemptId,
		"Status":        callback.Status,
		"Description":   callback.Description,
		"ExpireAt":      callback.ExpireAt,
		"NextCallAt":    model.UtcTime(callback.NextCallAt),
		"StickyAgentId": callback.StickyAgentId,
		"MaxAttempts":   maxAttempts,
		"WaitBetween":   waitBetween,
		"ExcludeDest":   callback.ExcludeCurrentCommunication,
		"PerNum":        perNum,
		"Vars":          callback.JsonVariables(),
	})

	if err != nil {
		code := extractCodeFromErr(err)
		if code == http.StatusNotFound {
			return nil, model.NewAppError("SqlMemberStore.SchemaResult", "store.sql_member.schema_result.not_found", nil,
				err.Error(), code)
		} else {
			return nil, model.NewAppError("SqlMemberStore.SchemaResult", "store.sql_member.schema_result.app_error", nil,
				err.Error(), code)
		}
	}

	return result, nil
}

func (s *SqlMemberStore) SaveToHistory() ([]*model.HistoryAttempt, *model.AppError) {
	var res []*model.HistoryAttempt

	_, err := s.GetMaster().Select(&res, `with del as materialized (
    select *
    from call_center.cc_member_attempt a
    where a.state = 'leaving' and not a.schema_processing is true 
    for update skip locked
    limit 100
),
dd as (
    delete
    from call_center.cc_member_attempt m
    where m.id in (
        select del.id
        from del
    )
)
insert
into call_center.cc_member_attempt_history (id, domain_id, queue_id, member_id, weight, resource_id, result,
                                agent_id, bucket_id, destination, display, description, list_communication_id,
                                joined_at, leaving_at, agent_call_id, member_call_id, offering_at, reporting_at,
                                bridged_at, channel, seq, resource_group_id, answered_at, team_id,
								transferred_at, transferred_agent_id, transferred_attempt_id, parent_id, node_id, form_fields, 
								import_id, variables)
select a.id, a.domain_id, a.queue_id, a.member_id, a.weight, a.resource_id, a.result, a.agent_id, a.bucket_id, a.destination,
       a.display, a.description, a.list_communication_id, a.joined_at, a.leaving_at, a.agent_call_id, a.member_call_id,
       a.offering_at, a.reporting_at, a.bridged_at, a.channel, a.seq, a.resource_group_id, a.answered_at, a.team_id,
	   a.transferred_at, a.transferred_agent_id, a.transferred_attempt_id, a.parent_id, a.node_id, a.form_fields, 
	   a.import_id, a.variables
from del a
returning id, result`)

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.SaveToHistory", "store.sql_member.save_history.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}
	return res, nil
}

func (s *SqlMemberStore) CreateConversationChannel(parentChannelId, name string, attemptId int64) (string, *model.AppError) {
	res, err := s.GetMaster().SelectStr(`insert into call_center.cc_msg_participants (name, conversation_id, attempt_id)
select :Name, parent.conversation_id, :AttemptId
from call_center.cc_msg_participants parent
    inner join call_center.cc_msg_conversation cmc on parent.conversation_id = cmc.id
where parent.channel_id = :Parent and cmc.closed_at is null
returning channel_id`, map[string]interface{}{
		"Name":      name,
		"AttemptId": attemptId,
		"Parent":    parentChannelId,
	})

	if err != nil {
		return "", model.NewAppError("SqlMemberStore.CreateConversationChannel", "store.sql_member.create_conv_channel.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}

	return res, nil

}

func (s *SqlMemberStore) RefreshQueueStatsLast2H() *model.AppError {
	_, err := s.GetMaster().Exec(`refresh materialized view CONCURRENTLY call_center.cc_distribute_stats`)

	if err != nil {
		return model.NewAppError("SqlAgentStore.RefreshAgentPauseCauses", "store.sql_agent.refresh_pause_cause.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}

	return nil
}

func (s *SqlMemberStore) TransferredTo(id, toId int64) *model.AppError {
	_, err := s.GetMaster().Exec(`select * from call_center.cc_attempt_transferred_to(:Id, :ToId)
			as x (last_state_change timestamptz)`, map[string]interface{}{
		"Id":   id,
		"ToId": toId,
	})
	if err != nil {
		return model.NewAppError("SqlMemberStore.TransferredTo", "store.sql_member.set_attempt_trans_to.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", id, err.Error()), http.StatusInternalServerError)
	}

	return nil
}

func (s *SqlMemberStore) TransferredFrom(id, toId int64, toAgentId int, toAgentSessId string) *model.AppError {
	_, err := s.GetMaster().Exec(`select * from call_center.cc_attempt_transferred_from(:Id::int8, :ToId::int8, :ToAgentId::int, :ToAgentSessId::varchar)
			as x (last_state_change timestamptz)`, map[string]interface{}{
		"Id":            id,
		"ToId":          toId,
		"ToAgentId":     toAgentId,
		"ToAgentSessId": toAgentSessId,
	})

	if err != nil {
		return model.NewAppError("SqlMemberStore.TransferredFrom", "store.sql_member.set_attempt_trans_from.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", id, err.Error()), http.StatusInternalServerError)
	}

	return nil
}

func (s *SqlMemberStore) CancelAgentDistribute(agentId int32) ([]int64, *model.AppError) {
	var res []int64
	_, err := s.GetMaster().Select(&res, `
		update call_center.cc_member_attempt att
		set result = 'cancel'
		from (
			select a.id
			from call_center.cc_member_attempt a
				inner join call_center.cc_queue q on q.id = a.queue_id
			where a.agent_id = :AgentId
			  and q.type != 5
			  and not exists(
					select 1
					from call_center.cc_member_attempt a2
					where a2.agent_id = :AgentId
					  and a2.agent_call_id notnull
						for update
				)
		) t
		where t.id = att.id
		returning att.id`, map[string]interface{}{
		"AgentId": agentId,
	})

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.CancelAgentDistribute", "store.sql_member.cancel_agent_distribute.app_error", nil,
			fmt.Sprintf("AgentId=%v %s", agentId, err.Error()), http.StatusInternalServerError)
	}

	return res, nil
}

func (s *SqlMemberStore) SetExpired(limit int) ([]*model.ExpiredMember, *model.AppError) {
	var res []*model.ExpiredMember
	_, err := s.GetMaster().Select(&res, `
			with upd as (
			update call_center.cc_member m
			set stop_cause = 'expired',
				stop_at = now()
			from (select m.id,
				   case when e.id notnull  then
					   jsonb_build_object('member_name', m.name) ||
					   jsonb_build_object('member_id', m.id::text) ||
					   jsonb_build_object('member_stop_cause', 'expired') ||
					   jsonb_build_object('cc_result', 'expired') ||
					   jsonb_build_object('queue_id', m.queue_id::text) ||
					   jsonb_build_object('cc_attempt_seq', m.attempts::text) ||
					   coalesce(m.variables, '{}') ||
					   coalesce(q.variables, '{}')
					   end variables,
				  e.schema_id,
				  m.id as member_id,
				  q.domain_id
			from call_center.cc_member m
				left join call_center.cc_queue_events e on e.queue_id = m.queue_id and e.enabled and e.event = 'leaving'
				left join call_center.cc_queue q on q.id = e.queue_id
			where m.expire_at < now()
				and m.stop_at isnull
			order by m.expire_at asc
			limit :Limit) t
			where t.id = m.id
			returning t.*
		)
		select upd.variables, upd.schema_id, upd.domain_id, upd.member_id
		from upd
		where upd.variables notnull`, map[string]interface{}{
		"Limit": limit,
	})

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.SetExpired", "store.sql_member.set_expired.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}

	return res, nil
}

func (s *SqlMemberStore) StoreForm(attemptId int64, form []byte, fields map[string]string) *model.AppError {
	_, err := s.GetMaster().Exec(`update call_center.cc_member_attempt
set form_view = :Form::jsonb,
    form_fields = coalesce(form_fields, '{}'::jsonb) || coalesce(:Fields::jsonb, '{}'::jsonb)
where id = :Id`, map[string]interface{}{
		"Id":     attemptId,
		"Form":   form,
		"Fields": mapToJson(fields),
	})

	if err != nil {
		return model.NewAppError("SqlMemberStore.StoreForm", "store.sql_member.set_form.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}

	return nil
}

func (s *SqlMemberStore) StoreFormFields(attemptId int64, fields map[string]string) *model.AppError {
	if fields == nil {
		return nil
	}
	_, err := s.GetMaster().Exec(`update call_center.cc_member_attempt
set form_fields = coalesce(form_fields, '{}'::jsonb) || :Fields::jsonb
where id = :Id`, map[string]interface{}{
		"Id":     attemptId,
		"Fields": mapToJson(fields),
	})

	if err != nil {
		return model.NewAppError("SqlMemberStore.StoreFormFields", "store.sql_member.set_form.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}

	return nil
}

func (s *SqlMemberStore) CleanAttempts(nodeId string) *model.AppError {
	_, err := s.GetMaster().Exec(`with u as (
    update call_center.cc_member_attempt a
    set result = 'restart',
        state = 'leaving',
        leaving_at = now()
    where a.node_id = :NodeId
    returning *
)
update call_center.cc_agent_channel c
    set channel = null,
        state = 'waiting'
where c.agent_id in (
    select distinct u.agent_id
    from u
    where u.agent_id notnull
)`, map[string]interface{}{
		"NodeId": nodeId,
	})

	if err != nil {
		return model.NewAppError("SqlMemberStore.CleanAttempts", "store.sql_member.clean_attempts.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}

	return nil
}

func (s *SqlMemberStore) FlipResource(attemptId int64, skippResources []int) (*model.AttemptFlipResource, *model.AppError) {
	var res *model.AttemptFlipResource
	err := s.GetMaster().SelectOne(&res, `select x.resource_id,
       x.resource_updated_at,
       x.gateway_updated_at,
       x.allow_call,
	   x.call_id	
from call_center.cc_attempt_flip_next_resource(:AttemptId::int8, :SkippResources::int[])
    as x(resource_id int, resource_updated_at int8, gateway_updated_at int8, allow_call bool, call_id varchar)`, map[string]interface{}{
		"AttemptId":      attemptId,
		"SkippResources": pq.Array(skippResources),
	})

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.FlipResource", "store.sql_member.flip_resource.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}

	return res, nil
}

func (s *SqlMemberStore) Intercept(ctx context.Context, domainId int64, attemptId int64, agentId int32) (int, *model.AppError) {
	var queueId int
	err := s.GetMaster().WithContext(ctx).SelectOne(&queueId, `update call_center.cc_member_attempt a
set agent_id = :AgentId,
    team_id = ag.team_id
from call_center.cc_agent ag
where a.id = :Id::int8
    and a.domain_id = :DomainId
    and a.agent_id isnull
    and ag.id = :AgentId
    and a.state = 'wait_agent'
returning a.queue_id`, map[string]interface{}{
		"DomainId": domainId,
		"AgentId":  agentId,
		"Id":       attemptId,
	})

	if err != nil {
		return 0, model.NewAppError("SqlMemberStore.Intercept", "store.sql_member.intercept.app_error", nil,
			err.Error(), extractCodeFromErr(err))
	}

	return queueId, nil
}

func (s *SqlMemberStore) addCommunications(memberId int64, comm []model.MemberCommunication) error {
	data, err := json.Marshal(comm)
	if err != nil {
		return err
	}
	_, err = s.GetMaster().Exec(`update call_center.cc_member
set communications = communications || :Comm::jsonb  
where id = :Id;`, map[string]interface{}{
		"Id":   memberId,
		"Comm": data,
	})

	if err != nil {
		return err
	}

	return nil
}

func (s *SqlMemberStore) WaitingList() ([]*model.MemberWaitingByUsers, *model.AppError) {
	var list []*model.MemberWaitingByUsers
	_, err := s.GetMaster().Select(&list, `select domain_id, users, chats, calls
from call_center.cc_manual_queue_list`)

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.WaitingList", "store.sql_member.waiting_list.app_error", nil,
			err.Error(), extractCodeFromErr(err))
	}

	return list, nil
}
