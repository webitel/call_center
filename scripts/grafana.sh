#!/bin/bash

docker run \
  -d \
  -p 3000:3000 \
  --name=grafana \
  -e "GF_SERVER_ROOT_URL=http://10.10.10.25" \
  -e "GF_SECURITY_ADMIN_PASSWORD=secret" \
  grafana/grafana