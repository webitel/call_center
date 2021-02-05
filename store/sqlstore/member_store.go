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
	if i, err := s.GetMaster().SelectNullInt(`call cc_distribute(null)`); err != nil {
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
			where id = :Id and state != :CancelState and result isnull`, map[string]interface{}{"Id": id, "State": model.MemberStateWaitAgent, "CancelState": model.MemberStateCancel}); err != nil {
		return model.NewAppError("SqlMemberStore.SetFindAgentState", "store.sql_member.set_attempt_state_find_agent.app_error", nil,
			fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
	}

	return nil
}

func (s SqlMemberStore) SetDistributeCancel(id int64, description string, nextDistributeSec uint32, stop bool, vars map[string]string) *model.AppError {
	_, err := s.GetMaster().Exec(`call cc_attempt_distribute_cancel(:Id::int8, :Desc::varchar, :NextSec::int4, :Stop::bool, :Vars::jsonb)`,
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

func (s SqlMemberStore) DistributeCallToQueue(node string, queueId int64, callId string, vars map[string]string, bucketId *int32, priority int) (*model.InboundCallQueue, *model.AppError) {
	var att *model.InboundCallQueue
	err := s.GetMaster().SelectOne(&att, `select *
from cc_distribute_inbound_call_to_queue(:AppId::varchar, :QueueId::int8, :CallId::varchar, :Variables::jsonb,
	:BucketId::int, :Priority::int)
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
		"AppId":     node,
		"QueueId":   queueId,
		"CallId":    callId,
		"Variables": model.MapToJson(vars),
		"BucketId":  bucketId,
		"Priority":  priority,
	})

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.DistributeCallToQueue", "store.sql_member.distribute_call.app_error", nil,
			fmt.Sprintf("QueueId=%v, CallId=%v %s", queueId, callId, err.Error()), http.StatusInternalServerError)
	}

	return att, nil
}

func (s SqlMemberStore) DistributeCallToQueueCancel(id int64) *model.AppError {
	_, err := s.GetMaster().Exec(`update cc_member_attempt
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

func (s SqlMemberStore) DistributeChatToQueue(node string, queueId int64, convId string, vars map[string]string, bucketId *int32, priority int) (*model.InboundChatQueue, *model.AppError) {
	var attempt *model.InboundChatQueue

	var v *string
	if vars != nil {
		v = new(string)
		*v = model.MapToJson(vars)
	}

	if err := s.GetMaster().SelectOne(&attempt, `select *
		from cc_distribute_inbound_chat_to_queue(:AppId::varchar, :QueueId::int8, :ConvId::varchar, :Variables::jsonb,
	:BucketId::int, :Priority::int) 
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
			"AppId":     node,
			"QueueId":   queueId,
			"ConvId":    convId,
			"Variables": v,
			"BucketId":  bucketId,
			"Priority":  priority,
		}); err != nil {
		return nil, model.NewAppError("SqlMemberStore.DistributeChatToQueue", "store.sql_member.distribute_chat.app_error", nil,
			fmt.Sprintf("QueueId=%v, Id=%v %s", queueId, convId, err.Error()), http.StatusInternalServerError)
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

func (s *SqlMemberStore) SetAttemptOffering(attemptId int64, agentId *int, agentCallId, memberCallId *string, destination, display *string) (int64, *model.AppError) {
	timestamp, err := s.GetMaster().SelectInt(`select cc_view_timestamp(x.last_state_change)::int8 as "timestamp"
from cc_attempt_offering(:AttemptId::int8, :AgentId::int4, :AgentCallId::varchar, :MemberCallId::varchar, :Dest::varchar, :Displ::varchar)
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
		return 0, model.NewAppError("SqlMemberStore.SetAttemptAbandoned", "store.sql_member.set_attempt_abandoned.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", attemptId, err.Error()), http.StatusInternalServerError)
	}

	return timestamp, nil
}

func (s *SqlMemberStore) SetAttemptAbandonedWithParams(attemptId int64, maxAttempts uint, sleep uint64) (int64, *model.AppError) {
	timestamp, err := s.GetMaster().SelectInt(`select cc_view_timestamp(x.last_state_change)::int8 as "timestamp"
from cc_attempt_abandoned(:AttemptId, :MaxAttempts, :Sleep)
    as x (last_state_change timestamptz)
where x.last_state_change notnull `, map[string]interface{}{
		"AttemptId":   attemptId,
		"MaxAttempts": maxAttempts,
		"Sleep":       sleep,
	})

	if err != nil {
		return 0, model.NewAppError("SqlMemberStore.SetAttemptAbandonedWithParams", "store.sql_member.set_attempt_abandoned.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", attemptId, err.Error()), http.StatusInternalServerError)
	}

	return timestamp, nil
}

func (s *SqlMemberStore) SetAttemptMissedAgent(attemptId int64, agentHoldSec int) (*model.MissedAgent, *model.AppError) {
	var res *model.MissedAgent
	err := s.GetMaster().SelectOne(&res, `select cc_view_timestamp(x.last_state_change)::int8 as "timestamp", no_answers
from cc_attempt_missed_agent(:AttemptId, :AgentHoldSec)
    as x (last_state_change timestamptz, no_answers int)
where x.last_state_change notnull `, map[string]interface{}{
		"AttemptId":    attemptId,
		"AgentHoldSec": agentHoldSec,
	})

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.SetAttemptMissedAgent", "store.sql_member.set_attempt_messed_agent.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", attemptId, err.Error()), http.StatusInternalServerError)
	}

	return res, nil
}

func (s *SqlMemberStore) SetAttemptReporting(attemptId int64, deadlineSec uint16) (int64, *model.AppError) {
	timestamp, err := s.GetMaster().SelectInt(`with att as (
    update cc_member_attempt
    set timeout  = case when :DeadlineSec::int > 0 then  now() + (:DeadlineSec::int || ' sec')::interval end,
        leaving_at = now(),
	    last_state_change = now(),
        state = :State
    where id = :Id
    returning agent_id, channel, state, leaving_at
)
update cc_agent_channel c
set state = att.state,
    joined_at = att.leaving_at
from att
where (att.agent_id, att.channel) = (c.agent_id, c.channel)
returning cc_view_timestamp(c.joined_at) as timestamp`, map[string]interface{}{
		"State":       model.ChannelStateWrapTime,
		"Id":          attemptId,
		"DeadlineSec": deadlineSec,
	})

	if err != nil {
		return 0, model.NewAppError("SqlMemberStore.SetAttemptReporting", "store.sql_member.set_attempt_reporting.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", attemptId, err.Error()), http.StatusInternalServerError)
	}

	return timestamp, nil
}

//TODO
func (s *SqlMemberStore) SetAttemptMissed(id int64, holdSec, agentHoldTime int) (int64, *model.AppError) {
	timestamp, err := s.GetMaster().SelectInt(`select cc_view_timestamp(cc_attempt_leaving(:Id::int8, :HoldSec::int, 'missed', :State, :AgentHoldTime)) as timestamp`,
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

func (s *SqlMemberStore) CancelAgentAttempt(id int64, agentHoldTime int) (*model.MissedAgent, *model.AppError) {
	var missed *model.MissedAgent
	err := s.GetMaster().SelectOne(&missed, `select cc_view_timestamp(x.last_state_change)::int8 as "timestamp", no_answers
from cc_attempt_agent_cancel(:AttemptId::int8, :Result::varchar, :AgentState::varchar, :AgentHoldSec::int4)
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
    update cc_member_attempt
        set leaving_at = now(),
            result = 'barred',
            state = 'leaving'
    where id = :AttemptId
    returning member_id, result
)
update cc_member m
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
		return 0, model.NewAppError("SqlMemberStore.SetAttemptResult", "store.sql_member.set_attempt_result.app_error", nil,
			fmt.Sprintf("AttemptId=%v %s", id, err.Error()), http.StatusInternalServerError)
	}

	return timestamp, nil
}

func (s *SqlMemberStore) GetTimeouts(nodeId string) ([]*model.AttemptReportingTimeout, *model.AppError) {
	var attempts []*model.AttemptReportingTimeout
	_, err := s.GetMaster().Select(&attempts, `select
       a.id attempt_id,
       cc_view_timestamp(cc_attempt_timeout(a.id, cq.sec_between_retries, 'abandoned', 'waiting', 0)) as timestamp,
       a.agent_id,
       ag.updated_at agent_updated_at,
       ag.user_id,
       ag.domain_id,
       a.channel
from cc_member_attempt a
    inner join cc_agent ag on ag.id = a.agent_id
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

func (s *SqlMemberStore) CallbackReporting(attemptId int64, status, description string, expireAt, nextDistributeAt *int64, agentId *int) (*model.AttemptReportingResult, *model.AppError) {
	var result *model.AttemptReportingResult
	err := s.GetMaster().SelectOne(&result, `select *
from cc_attempt_end_reporting(:AttemptId::int8, :Status, :Description, :ExpireAt, :NextDistributeAt, :StickyAgentId) as
x (timestamp int8, channel varchar, queue_id int, agent_call_id varchar, agent_id int, user_id int8, domain_id int8, agent_timeout int8)
where x.queue_id notnull`, map[string]interface{}{
		"AttemptId":        attemptId,
		"Status":           status,
		"Description":      description,
		"ExpireAt":         expireAt,
		"NextDistributeAt": nextDistributeAt,
		"StickyAgentId":    agentId,
	})

	if err != nil {
		code := extractCodeFromErr(err)
		if code == http.StatusNotFound {
			return nil, model.NewAppError("SqlMemberStore.Reporting", "store.sql_member.reporting.not_found", nil,
				err.Error(), code)
		} else {
			return nil, model.NewAppError("SqlMemberStore.Reporting", "store.sql_member.reporting.app_error", nil,
				err.Error(), code)
		}

	}

	return result, nil
}

func (s SqlMemberStore) SaveToHistory() ([]*model.HistoryAttempt, *model.AppError) {
	var res []*model.HistoryAttempt

	_, err := s.GetMaster().Select(&res, `with del as (
    delete
        from cc_member_attempt a
    where a.state = 'leaving'
    returning *
)
insert
into cc_member_attempt_history (id, domain_id, queue_id, member_id, weight, resource_id, result,
                                agent_id, bucket_id, destination, display, description, list_communication_id,
                                joined_at, leaving_at, agent_call_id, member_call_id, offering_at, reporting_at,
                                bridged_at, channel, seq)
select a.id, domain_id, a.queue_id, a.member_id, a.weight, a.resource_id, a.result, a.agent_id, a.bucket_id, a.destination,
       a.display, a.description, a.list_communication_id, a.joined_at, a.leaving_at, a.agent_call_id, a.member_call_id,
       a.offering_at, a.reporting_at, a.bridged_at, a.channel, a.seq
from del a
    inner join cc_queue q on q.id = a.queue_id
returning cc_member_attempt_history.id, cc_member_attempt_history.result`)

	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.SaveToHistory", "store.sql_member.save_history.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}
	return res, nil
}

func (s SqlMemberStore) CreateConversationChannel(parentChannelId, name string, attemptId int64) (string, *model.AppError) {
	res, err := s.GetMaster().SelectStr(`insert into cc_msg_participants (name, conversation_id, attempt_id)
select :Name, parent.conversation_id, :AttemptId
from cc_msg_participants parent
    inner join cc_msg_conversation cmc on parent.conversation_id = cmc.id
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
