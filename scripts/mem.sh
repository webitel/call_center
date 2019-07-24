#!/bin/bash

go tool pprof -inuse_objects ./build/call_center http://localhost:8090/debug/pprof/heap