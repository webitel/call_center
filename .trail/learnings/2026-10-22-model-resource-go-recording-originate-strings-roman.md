---
title: "model/resource.go: recording originate strings need RECORD_MIN_SEC"
author: Roman
date: 2026-10-22
standing: true
id: l-d2476ea1
scope: repo
status: active
touches:
  - model/resource.go
---

## Decided
The recording originate string built in `model/resource.go` (the `hangup_after_bridge=true,recording_follow_transfer=true,RECORD_BRIDGE_REQ=...,execute_on_answer=wbt_record_session ...` format) should set `RECORD_MIN_SEC`. The agreed value is `minSec: 2`. Without it FreeSWITCH uses its own default of 3 seconds, which affects preview and offline recordings.
Queue recordings already lacked it before this change. When you touch this string, add it.
Example: in PR #362, the queue-call recording string was changed to `wbt_record_session` and the reviewer pointed out `RECORD_MIN_SEC` was missing.

_From review on #362 here, merged Oct 22._
