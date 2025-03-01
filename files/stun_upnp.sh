#!/bin/bash

# 初始化变量
UPNP_INPORT=$1
UPNP_EXPORT=$2
L4PROTO=$3
[ -f StunUpnpInterface ] && StunUpnpInterface='br-lan'

# 定义日志函数
LOG() { echo "$*" | tee -a /BitComet/DockerLogs.log ;}

LOG 本次 UPnP 规则：转发 外部端口 $UPNP_EXPORT/$L4PROTO 至 内部端口 $UPNP_INPORT/$L4PROTO

# 定义执行函数
ADD_UPNP() {
	[ $StunUpnpInterface ] && local StunUpnpInterface='-m '$StunUpnpInterface''
	[ $StunUpnpUrl ] && local StunUpnpUrl='-u '$StunUpnpUrl''
	[ $StunUpnpAddr ] || local StunUpnpAddr=@
	UPNP_START='upnpc '$StunUpnpArgs' '$StunUpnpInterface' '$StunUpnpUrl' -i -e "STUN BitComet Docker" -a '$StunUpnpAddr' '$UPNP_INPORT' '$UPNP_EXPORT' '$L4PROTO''
	UPNP_RES=$(eval $UPNP_START 2>&1)
	UPNP_FLAG=$?
	[ $UPNP_FLAG = 0 ] && LOG 更新 UPnP 规则成功
}

ADD_UPNP

[ $UPNP_FLAG = 1 ] && [[ $UPNP_RES == *'No IGD UPnP Device found on the network'* ]] && [ "$StunUpnpInterface" != '-m br-lan' ] && [ $(ls /sys/class/net | grep ^br-lan$) ] && {
	LOG 未找到 IGD UPnP 设备，尝试使用 br-lan 接口
	StunUpnpInterface='br-lan'
	ADD_UPNP
	[[ $UPNP_FLAG =~ ^[02]$ ]] && echo br-lan >StunUpnpInterface
}

[[ ! $StunMode =~ nft ]] && [ $UPNP_FLAG = 2 ] && [[ $UPNP_RES == *'ConflictWithOtherMechanisms'* ]] && \
([ ! -f StunUpnpConflict_$L4PROTO ] || [ $(($(date +%s)-$(stat -c %Y StunUpnpConflict_$L4PROTO))) -gt 3600 ]) && {
	LOG IGD UPnP 设备检测到端口占用，等待释放，最大限时 300 秒
	>StunUpnpConflict_$L4PROTO
	[ $L4PROTO = tcp ] && pkill -f stun_keep.sh
	timeout 300 bash -c "while awk '{print\$2}' /proc/net/$L4PROTO /proc/net/${L4PROTO}6 | grep -qi ":$(printf '%04x' $UPNP_EXPORT)"; do sleep 1; done"
	if [ $? = 0 ]; then
		LOG 端口释放成功，继续尝试更新 UPnP 规则
	else
		LOG 端口释放失败，请确认正在使用 $UPNP_EXPORT/$L4PROTO 的程序，仍继续尝试更新 UPnP 规则
	fi
	until [ $UPNP_FLAG = 0 ] || [ "$UPNP_TRY" = 5 ]; do
		let UPNP_TRY++
		LOG UPnP 第 $UPNP_TRY 次重试，最多 5 次
		ADD_UPNP
		[ $UPNP_FLAG = 0 ] || [ $UPNP_TRY = 5 ] || sleep 15
	done
	[ $L4PROTO = tcp ] && ! pgrep -f stun_keep.sh >/dev/null && setsid stun_keep.sh &
}

[ $UPNP_FLAG = 0 ] && rm -f StunUpnpConflict_$L4PROTO
[ $UPNP_FLAG = 1 ] && LOG 更新 UPnP 规则失败，错误信息如下 && LOG "$UPNP_RES" | head -1
[ $UPNP_FLAG = 2 ] && LOG 更新 UPnP 规则失败，错误信息如下 && LOG "$UPNP_RES" | tail -1
