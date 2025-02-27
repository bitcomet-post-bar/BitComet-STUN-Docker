#!/bin/bash

# 初始化变量
WANADDR=$1
WANPORT=$2
LANPORT=$3
L4PROTO=$4

APPPORT=$STUN_ORIG_PORT

# 定义日志函数
LOG() { echo "$*" | tee -a /BitComet/DockerLogs.log ;}

LOG 本次穿透通道为 $WANADDR:$WANPORT

# 防止脚本重复运行
pkill -Af "$0 $*"

# 初始化穿透信息
touch /BitComet/DockerStun.log
[ $(wc -l </BitComet/DockerStun.log) -ge 1000 ] && mv /BitComet/DockerStun.log /BitComet/DockerStun.log.old
echo $WANPORT $LANPORT >StunPort_$L4PROTO

# 传统模式
[[ $StunMode =~ nft ]] || {
	echo [$(date)] $WANADDR:$WANPORT '->' :$LANPORT '->' :$WANPORT >>/BitComet/DockerStun.log
	LOG 当前为传统模式，更新 BitComet 监听端口
	/files/BitComet/bin/bitcometd --bt_port $WANPORT >/dev/null
}

# 改包模式
[[ $StunMode =~ nft ]] && {
	echo [$(date)] $WANADDR:$WANPORT '->' :$APPPORT >>/BitComet/DockerStun.log
	LOG 当前为改包模式，更新 nftables 规则
	nftables.sh $@
}

# UPnP
[ "$StunUpnp" = 0 ] || {
	LOG 已启用 UPnP
	ADD_UPNP() {
		[ $StunUpnpInterface ] && local StunUpnpInterface='-m '$StunUpnpInterface''
		[ $StunUpnpUrl ] && local StunUpnpUrl='-u '$StunUpnpUrl''
		[ $StunUpnpAddr ] || local StunUpnpAddr=@
		UPNP_START='upnpc '$StunUpnpArgs' '$StunUpnpInterface' '$StunUpnpUrl' -i -e "STUN BitComet Docker" -a '$StunUpnpAddr' '$UPNP_INPORT' '$UPNP_EXPORT' '$L4PROTO''
		[ $UPNP_TRY ] || {
			LOG 本次 UPnP 执行命令
			LOG $UPNP_START
		}
		UPNP_RES=$(eval $UPNP_START 2>&1)
		UPNP_FLAG=$?
		[ $UPNP_FLAG = 0 ] && LOG 更新 UPnP 规则成功
	}
	[ -f StunUpnpInterface ] && export StunUpnpInterface='br-lan'
	[[ $StunMode =~ nft ]] || {
		UPNP_INPORT=$WANPORT
		UPNP_EXPORT=$LANPORT
	}
	[[ $StunMode =~ nft ]] && {
		UPNP_INPORT=$APPPORT
		UPNP_EXPORT=$APPPORT
	}
	LOG 本次 UPnP 规则：转发 外部端口 $UPNP_EXPORT/$L4PROTO 至 内部端口 $UPNP_INPORT/$L4PROTO
	ADD_UPNP
	[ $UPNP_FLAG = 1 ] && [[ $UPNP_RES == *'No IGD UPnP Device found on the network'* ]] && [ "$StunUpnpInterface" != '-m br-lan' ] && \
	[ $(ls /sys/class/net | grep ^br-lan$) ] && {
		LOG 未找到 IGD UPnP 设备，尝试使用 br-lan 接口
		export StunUpnpInterface='br-lan'
		ADD_UPNP
		[[ $UPNP_FLAG =~ ^[02]$ ]] && echo br-lan >StunUpnpInterface
	}
	[ $UPNP_FLAG = 1 ] && LOG 更新 UPnP 规则失败，错误信息如下 && LOG "$UPNP_RES" | head -1
	[ $UPNP_FLAG = 2 ] && LOG 更新 UPnP 规则失败，错误信息如下 && LOG "$UPNP_RES" | tail -1
}
