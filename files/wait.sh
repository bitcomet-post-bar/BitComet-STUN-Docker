#!/bin/bash
EXIT() {
	kill -15 $(ps ax | awk '{print$1}' | grep -vE '^(PID|1)$') 2>/dev/null
}
trap EXIT SIGTERM
sleep infinity &
wait
