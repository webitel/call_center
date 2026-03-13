
drop view portal.sip_subscriber;
create view portal.sip_subscriber as
SELECT row_number() OVER ()                             AS id,
       stk.dc,
       stk.id                                           AS grant_id,
       sip.schema_id,
       dst.caller_id_name,
       usr.contact_id,
       sip.host,
       pdc.name                                         AS realm,
       dst.user_id,
       dst.auth_id,
       encode(digest(dst.a1, 'md5'::text), 'hex'::text) AS digest_ha1,
       null::int8 uid
FROM portal.session stk
       JOIN portal.device dev ON dev.id = stk.device_id
       JOIN directory.wbt_domain pdc ON pdc.dc = stk.dc
       JOIN portal.service_sip sip ON sip.id = stk.service_id
       JOIN portal.user_service aud ON aud.id = stk.account_id
       JOIN portal.user_account usr ON usr.id = aud.account_id
       JOIN portal.identity idt ON idt.id = usr.profile_id
       LEFT JOIN contacts.contact cnt ON cnt.id = usr.contact_id
       JOIN LATERAL ( SELECT stk.dc,
                             pdc.name                                                                            AS realm,
                             COALESCE(cnt.common_name, idt.name)                                                 AS caller_id_name,
                             aud.sip_user                                                                        AS user_id,
                             dev.sub                                                                             AS auth_id,
                             (((dev.sub || ':'::text) || lower(pdc.name::text)) || ':'::text) ||
                             stk.token::text                                                                     AS a1) dst
            ON true
WHERE stk.token IS NOT NULL
  AND COALESCE(stk.rotated_at, stk.created_at) <= timezone('utc'::text, now())
  AND COALESCE(timezone('utc'::text, now()) < stk.expires_at, true);
