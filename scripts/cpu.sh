#!/bin/bash

go tool pprof ./build/call_center "http://localhost:8090/debug/pprof/profile?seconds=5"