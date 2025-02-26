#!/bin/bash
EXIT() {
	echo 正在停止容器 | tee -a /BitComet/DockerLogs.log
	kill -15 $(ps ax | awk '{print$1}' | grep -vE '^(PID|1)$') 2>/dev/null
}
trap EXIT SIGTERM
sleep infinity &
wait
