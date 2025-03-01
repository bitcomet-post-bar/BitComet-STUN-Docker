#!/bin/bash

# 初始化变量
WANADDR=$1
WANPORT=$2
LANPORT=$3
L4PROTO=$4

APPPORT=$STUN_ORIG_PORT

# 定义日志函数
LOG() { echo "$*" | tee -a /BitComet/DockerLogs.log ;}

LOG 本次穿透通道为 $WANADDR:$WANPORT/$L4PROTO

# 防止脚本重复运行
pkill -Af $0.*$L4PROTO

# 初始化穿透信息
touch /BitComet/DockerStun.log
[ $(wc -l </BitComet/DockerStun.log) -ge 1000 ] && mv /BitComet/DockerStun.log /BitComet/DockerStun.log.old
echo $WANPORT $LANPORT >StunPort_$L4PROTO

# 传统模式
[[ $StunMode =~ nft ]] || {
	echo [$(date)] $L4PROTO $WANADDR:$WANPORT '->' :$LANPORT '->' :$WANPORT >>/BitComet/DockerStun.log
	LOG 当前为传统模式，更新 BitComet 监听端口
	/files/BitComet/bin/bitcometd --bt_port $WANPORT >/dev/null
}

# 改包模式
[[ $StunMode =~ nft ]] && {
	echo [$(date)] $L4PROTO $WANADDR:$WANPORT '->' :$APPPORT >>/BitComet/DockerStun.log
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
#		[ $UPNP_TRY ] || {
#			LOG 本次 UPnP 执行命令
#			LOG $UPNP_START
#		}
		UPNP_RES=$(eval $UPNP_START 2>&1)
		UPNP_FLAG=$?
		[ $UPNP_FLAG = 0 ] && LOG 更新 UPnP 规则成功
	}
	[ -f StunUpnpInterface ] && StunUpnpInterface='br-lan'
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
	[ $UPNP_FLAG = 1 ] && [[ $UPNP_RES == *'No IGD UPnP Device found on the network'* ]] && [ "$StunUpnpInterface" != '-m br-lan' ] && [ $(ls /sys/class/net | grep ^br-lan$) ] && {
		LOG 未找到 IGD UPnP 设备，尝试使用 br-lan 接口
		StunUpnpInterface='br-lan'
		ADD_UPNP
		[[ $UPNP_FLAG =~ ^[02]$ ]] && echo br-lan >StunUpnpInterface
	}
	[ $UPNP_FLAG = 2 ] && [[ $UPNP_RES == *'ConflictWithOtherMechanisms'* ]] && \
	awk '{print$2}' /proc/net/$L4PROTO /proc/net/${L4PROTO}6 | grep -qi ":$(printf '%04x' $LANPORT)" && \
	([ ! -f StunUpnpConflict_$L4PROTO ] || [ $(($(date +%s)-$(stat -c %Y StunUpnpConflict_$L4PROTO))) -gt 3600 ]) && {
		LOG IGD UPnP 设备启用了端口占用检测
		>StunUpnpConflict_$L4PROTO
		if pgrep -f stun_keep.sh >/dev/null; then
			LOG 结束 HTTP 保活并等待端口释放，最大限时 300 秒
			pkill -f stun_keep.sh
			timeout 300 bash -c "while awk '{print\$2}' /proc/net/$L4PROTO | grep -qi ":$(printf '%04x' $UPNP_EXPORT)"; do sleep 1; done"
			if [ $? = 0 ]; then
				LOG 端口释放成功，继续尝试更新 UPnP 规则
			else
				LOG 端口释放失败，仍继续尝试更新 UPnP 规则
			fi
		else
			LOG 请确认正在使用 $UPNP_EXPORT/$L4PROTO 的程序，仍继续尝试更新 UPnP 规则
		fi
		until [ $UPNP_FLAG = 0 ] || [ "$UPNP_TRY" = 5 ]; do
			let UPNP_TRY++
			LOG UPnP 第 $UPNP_TRY 次重试，最多 5 次
			ADD_UPNP
			[ $UPNP_FLAG = 0 ] || [ $UPNP_TRY = 5 ] || sleep 15
		done
		[ $UPNP_FLAG = 0 ] && rm -f StunUpnpConflict_$L4PROTO
	}
	[ $UPNP_FLAG = 1 ] && LOG 更新 UPnP 规则失败，错误信息如下 && LOG "$UPNP_RES" | head -1
	[ $UPNP_FLAG = 2 ] && LOG 更新 UPnP 规则失败，错误信息如下 && LOG "$UPNP_RES" | tail -1
}

# TCP 通道保活
[ $L4PROTO = tcp ] && ! pgrep -f stun_keep.sh >/dev/null && {
	LOG 已启用 TCP 通道，执行 HTTP 保活
	LOG 若保活失败，穿透通道可能需要在缩短心跳间隔后才稳定
	stun_keep.sh &
}

# 连通性检测
until echo | socat - $L4PROTO:$WANADDR:$WANPORT,connect-timeout=2 2>/dev/null; do
	let STUN_CHECK++
	[ $STUN_CHECK -ge 10 ] && break
	sleep 1
done
if [ $STUN_CHECK ] && [ $STUN_CHECK -ge 10 ]; then
	LOG $WANADDR:$WANPORT/$L4PROTO 连通性检测失败，请确认路径上的防火墙
else
	LOG $WANADDR:$WANPORT/$L4PROTO 连通性检测成功
	pkill -10 -f stun.sh
fi
