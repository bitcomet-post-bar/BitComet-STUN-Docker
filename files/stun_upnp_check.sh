#!/bin/bash

# 初始化变量
WANADDR=$1
WANPORT=$2
LANPORT=$3
L4PROTO=$4

# 定义日志函数
LOG() { echo "$*" | tee -a /BitComet/DockerLogs.log ;}

# 防止脚本重复运行
pkill -Af $0.*$L4PROTO

# 检测 UPnP 规则有效性
while :; do
	[ $STUN_UPNP_CHECK ] || sleep $(($StunInterval*10))
	[ $STUN_UPNP_CHECK ] && sleep $(($StunInterval/$STUN_UPNP_KEEP))
	if echo | socat - $L4PROTO:$WANADDR:$WANPORT,connect-timeout=2 2>/dev/null; then
		unset STUN_UPNP_CHECK
	else
		let STUN_UPNP_CHECK++
	fi
	[ "$STUN_UPNP_CHECK" = 10 ] && {
		[[ $StunMode =~ nft ]] && stun_upnp.sh $APPPORT $APPPORT $L4PROTO
		[[ $StunMode =~ nft ]] || stun_upnp.sh $WANPORT $LANPORT $L4PROTO
	}
done
