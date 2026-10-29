CREATE OR REPLACE VIEW "storage"."files_list" AS
 SELECT
    f.id,
    f.name,
    f.view_name,
    f.size,
    f.mime_type,
    f.uuid,
    f.uuid AS reference_id,
    storage.get_lookup(p.id, p.name::character varying) AS profile,
    f.uploaded_at,
    storage.get_lookup(u.id, COALESCE(u.username::character varying, u.name::character varying)) AS uploaded_by,
    f.sha256sum,
    f.channel,
    f.thumbnail,
    f.retention_until,
    f.domain_id,
    f.profile_id,
    f.created_at,
    f.properties,
    f.instance,
    f.uploaded_by AS uploaded_by_id,
    f.removed,
    f.custom_properties as custom_properties
   FROM storage.files f
     LEFT JOIN storage.file_backend_profiles p ON p.id = f.profile_id
     LEFT JOIN directory.wbt_user u ON u.id = f.uploaded_by;
