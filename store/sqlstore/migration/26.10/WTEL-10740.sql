-- WTEL-10740: remove routing schema versioning (WTEL-3033).
-- Schema changes are audited by webitel-logger (logger.log), so flow.scheme_version is redundant.

drop trigger if exists insert_flow_version on flow.acr_routing_scheme;
drop function if exists flow.scheme_version_appeared();

drop table if exists flow.scheme_version;
drop sequence if exists flow.scheme_version_id_seq;

delete from call_center.system_settings
where name = 'scheme_version_limit';
