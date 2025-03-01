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
	[[ $StunMode =~ nft ]] && stun_upnp.sh $APPPORT $APPPORT $L4PROTO
	[[ $StunMode =~ nft ]] || stun_upnp.sh $WANPORT $LANPORT $L4PROTO
}

# TCP 通道保活
[ $L4PROTO = tcp ] && ! pgrep -f stun_keep.sh >/dev/null && {
	LOG 已启用 TCP 通道，执行 HTTP 保活
	LOG 若保活失败，穿透通道可能需要在缩短心跳间隔后才稳定
	setsid stun_keep.sh &
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
	[ $L4PROTO = tcp ] && pkill -10 -f stun.sh
fi
