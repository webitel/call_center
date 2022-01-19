alter table call_center.cc_agent drop constraint cc_agent_wbt_user_id_fk_2;

alter table call_center.cc_agent
    add constraint cc_agent_wbt_user_id_fk_2
        foreign key (created_by) references directory.wbt_user
            on delete set null;

alter table call_center.cc_agent drop constraint cc_agent_wbt_user_id_fk_3;

alter table call_center.cc_agent
    add constraint cc_agent_wbt_user_id_fk_3
        foreign key (updated_by) references directory.wbt_user
            on delete set null;


alter table call_center.cc_bucket drop constraint cc_bucket_wbt_user_id_fk;

alter table call_center.cc_bucket
    add constraint cc_bucket_wbt_user_id_fk
        foreign key (created_by) references directory.wbt_user
            on delete set null;

alter table call_center.cc_bucket drop constraint cc_bucket_wbt_user_id_fk_2;

alter table call_center.cc_bucket
    add constraint cc_bucket_wbt_user_id_fk_2
        foreign key (updated_by) references directory.wbt_user
            on delete set null;



alter table call_center.cc_list alter column created_by drop not null;

alter table call_center.cc_list alter column updated_by drop not null;

alter table call_center.cc_list drop constraint cc_list_wbt_user_id_fk;

alter table call_center.cc_list
    add constraint cc_list_wbt_user_id_fk
        foreign key (created_by) references directory.wbt_user
            on delete set null;

alter table call_center.cc_list drop constraint cc_list_wbt_user_id_fk_2;

alter table call_center.cc_list
    add constraint cc_list_wbt_user_id_fk_2
        foreign key (updated_by) references directory.wbt_user
            on delete set null;


--
alter table call_center.cc_calls_annotation alter column created_by drop not null;

alter table call_center.cc_calls_annotation alter column updated_by drop not null;


alter table call_center.cc_calls_annotation alter column created_by set not null;

alter table call_center.cc_calls_annotation alter column updated_by set not null;

alter table call_center.cc_calls_annotation drop constraint cc_calls_annotation_wbt_user_id_fk;

alter table call_center.cc_calls_annotation
    add constraint cc_calls_annotation_wbt_user_id_fk
        foreign key (created_by) references directory.wbt_user
            on delete set null;

alter table call_center.cc_calls_annotation drop constraint cc_calls_annotation_wbt_user_id_fk_2;

alter table call_center.cc_calls_annotation
    add constraint cc_calls_annotation_wbt_user_id_fk_2
        foreign key (updated_by) references directory.wbt_user
            on delete set null;


---
alter table call_center.cc_outbound_resource alter column created_by drop not null;

alter table call_center.cc_outbound_resource alter column updated_by drop not null;



alter table call_center.cc_outbound_resource drop constraint cc_outbound_resource_wbt_user_id_fk;

alter table call_center.cc_outbound_resource
    add constraint cc_outbound_resource_wbt_user_id_fk
        foreign key (created_by) references directory.wbt_user
            on delete set null;

alter table call_center.cc_outbound_resource drop constraint cc_outbound_resource_wbt_user_id_fk_2;

alter table call_center.cc_outbound_resource
    add constraint cc_outbound_resource_wbt_user_id_fk_2
        foreign key (updated_by) references directory.wbt_user
            on delete set null;





create or replace procedure call_center.cc_call_set_bridged(call_id_ character varying, state_ character varying, timestamp_ timestamp with time zone, app_id_ character varying, domain_id_ bigint, call_bridged_id_ character varying)
    language plpgsql
as $$
declare
    transfer_to_ varchar;
    transfer_from_ varchar;
begin
    update call_center.cc_calls cc
    set bridged_id = c.bridged_id,
        state      = state_,
        timestamp  = timestamp_,
        to_number  = case
                         when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound' and cc.gateway_id isnull )
                             then c.number_
                         else to_number end,
        to_name    = case
                         when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound' and cc.gateway_id isnull )
                             then c.name_
                         else to_name end,
        to_type    = case
                         when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound' and cc.gateway_id isnull )
                             then c.type_
                         else to_type end,
        to_id      = case
                         when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound'  and cc.gateway_id isnull )
                             then c.id_
                         else to_id end
    from (
             select b.id,
                    b.bridged_id as transfer_to,
                    b2.id parent_id,
                    b2.id bridged_id,
                    b2o.*
             from call_center.cc_calls b
                      left join call_center.cc_calls b2 on b2.id = call_id_
                      left join lateral call_center.cc_call_get_owner_leg(b2) b2o on true
             where b.id = call_bridged_id_
         ) c
    where c.id = cc.id
    returning c.transfer_to into transfer_to_;


    update call_center.cc_calls cc
    set bridged_id    = c.bridged_id,
        state         = state_,
        timestamp     = timestamp_,
        parent_id     = case
                            when c.is_leg_a is true and cc.parent_id notnull and cc.parent_id != c.bridged_id then c.bridged_id
                            else cc.parent_id end,
        transfer_from = case
                            when cc.parent_id notnull and cc.parent_id != c.bridged_id then cc.parent_id
                            else cc.transfer_from end,
        transfer_to = transfer_to_,
        to_number     = case
                            when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound')
                                then c.number_
                            else to_number end,
        to_name       = case
                            when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound')
                                then c.name_
                            else to_name end,
        to_type       = case
                            when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound')
                                then c.type_
                            else to_type end,
        to_id         = case
                            when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound')
                                then c.id_
                            else to_id end
    from (
             select b.id,
                    b2.id parent_id,
                    b2.id bridged_id,
                    b.parent_id isnull as is_leg_a,
                    b2o.*
             from call_center.cc_calls b
                      left join call_center.cc_calls b2 on b2.id = call_bridged_id_
                      left join lateral call_center.cc_call_get_owner_leg(b2) b2o on true
             where b.id = call_id_
         ) c
    where c.id = cc.id
    returning cc.transfer_from into transfer_from_;

    update call_center.cc_calls set
                                    transfer_from =  case when id = transfer_from_ then transfer_to_ end,
                                    transfer_to =  case when id = transfer_to_ then transfer_from_ end
    where id in (transfer_from_, transfer_to_);

end;
$$;