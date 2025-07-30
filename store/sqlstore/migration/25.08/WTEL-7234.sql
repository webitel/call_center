DROP INDEX IF EXISTS cc_preset_query_user_id_name_uindex;

ALTER TABLE call_center.cc_preset_query
ADD CONSTRAINT cc_preset_query_user_id_section_name_uindex
UNIQUE (user_id, section, name);