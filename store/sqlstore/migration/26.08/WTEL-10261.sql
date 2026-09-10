drop VIEW if exists flow.acr_routing_outbound_call_view;

alter table flow.acr_routing_outbound_call
    add column allow_transfer boolean DEFAULT false NOT NULL;

--
-- Name: acr_routing_outbound_call_view; Type: VIEW; Schema: flow; Owner: -
--

CREATE VIEW flow.acr_routing_outbound_call_view AS
SELECT tmp.id,
       tmp.domain_id,
       tmp.scheme_id                                       AS schema_id,
       tmp.name,
       tmp.description,
       tmp.created_at,
       flow.get_lookup(c.id, (c.name)::character varying) AS created_by,
       flow.get_lookup(u.id, (u.name)::character varying) AS updated_by,
       tmp.pattern,
       tmp.disabled,
       tmp.allow_transfer,
       flow.get_lookup(arst.id, arst.name)                 AS schema,
       row_number() OVER (PARTITION BY tmp.domain_id ORDER BY tmp.pos DESC) AS "position"
FROM (((flow.acr_routing_outbound_call tmp
    JOIN flow.acr_routing_scheme arst ON ((tmp.scheme_id = arst.id)))
    LEFT JOIN directory.wbt_user c ON ((c.id = tmp.created_by)))
    LEFT JOIN directory.wbt_user u ON ((u.id = tmp.updated_by)));
