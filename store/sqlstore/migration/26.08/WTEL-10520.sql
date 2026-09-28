update flow.acr_routing_outbound_call
set allow_transfer = true
where allow_transfer = false
  and updated_at < 1790053731000;
