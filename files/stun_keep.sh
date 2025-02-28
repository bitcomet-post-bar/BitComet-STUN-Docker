#!/bin/bash

# 定义日志函数
LOG() { echo "$*" | tee -a /BitComet/DockerLogs.log ;}

# 防止脚本重复运行
pkill -Af "$0 $*"

# 更新 HTTP 服务器
UPDATE_HTTP() {
	LOG 更新 HTTP 服务器列表，最多等待 15 秒
	echo -ne "GET /topsite_ip.txt HTTP/1.1\r\nHost: oniicyan.pages.dev\r\nConnection: close\r\n\r\n" | \
	timeout 15 openssl s_client -connect oniicyan.pages.dev:443 -quiet 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' >/tmp/SiteList.txt
	if [ -s /tmp/SiteList.txt ]; then
		LOG 更新 HTTP 服务器列表成功
		mv -f /tmp/SiteList.txt SiteList.txt
	else
		LOG 更新 HTTP 服务器列表失败，本次跳过
		[ -f SiteList.txt ] || cp /files/SiteList.txt SiteList.txt
	fi
	sort -R SiteList.txt >/tmp/SiteList.txt
	LOG 已加载 $(wc -l </tmp/SiteList.txt) 个 HTTP 服务器
}

# 穿透通道保活
KEEPALIVE() {
	unset STUN_KEEP_FLAG
	for SERVER in $(cat /tmp/SiteList.txt); do
		local START=$(date +%s)
		local RES=$(echo -ne "HEAD / HTTP/1.1\r\nHost: $SERVER\r\nConnection: keep-alive\r\n\r\n" | eval runuser -u socat -- socat -,ignoreeof tcp4:$SERVER:80,connect-timeout=2,reuseport,sourceport=$STUN_BIND_PORT$STUN_IFACE 2>&1)
		if [ $(($(date +%s)-$START)) -gt 60 ]; then
			let STUN_KEEP_FLAG++
		else
			sed '/^'$SERVER'$/d' -i /tmp/SiteList.txt
		fi
	done
}

# 循环执行
while :; do
	[ -s /tmp/SiteList.txt ] || UPDATE_HTTP
	STUN_KEEP_START=$(date +%s)
	KEEPALIVE
	if [ $STUN_KEEP_FLAG ]; then
		LOG 本次循环共保活 $(($(date +%s)-$STUN_KEEP_START)) 秒
	else
		LOG 保活失败，3600 秒后重试
		LOG 穿透通道可能需要在自动缩短心跳间隔后稳定
		sleep 3600
	fi
done
