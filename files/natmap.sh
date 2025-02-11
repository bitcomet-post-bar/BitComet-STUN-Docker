#!/bin/bash

WANADDR=$1
WANPORT=$2
LANPORT=$4
L4PROTO=$5
OWNADDR=$6

# 定义日志函数
LOG() { tee -a /BitComet/DockerLogs.log ;}

# 检测是否触发 UPnP 兼容模式
rm /BitComet/DockerStunUpnpConflict_$L4PROTO 2>/dev/null && \
if [ $2 = $(awk '{print$1}' /BitComet/DockerStunPort_$L4PROTO) ] && [ $4 = $(awk '{print$2}' /BitComet/DockerStunPort_$L4PROTO) ]; then
	echo 穿透通道已保持，无需操作 | LOG
	exit
else
	echo 穿透通道已变更，重新操作 | LOG
fi

echo 当前穿透通道为 $WANADDR:$WANPORT | LOG

# 防止脚本重复运行
while :; do
	ps x | grep $0 | grep $L4PROTO | grep -vE ''$$'|grep|' | awk 'NR==1{print$1}' | xargs kill >/dev/null 2>&1 || break
done

# 保存穿透信息
touch /BitComet/DockerStun.log
[ $(wc -l </BitComet/DockerStun.log) -ge 1000 ] && mv /BitComet/DockerStun.log /BitComet/DockerStun.log.old
echo [$(date)] $WANADDR:$WANPORT '->' $OWNADDR:$LANPORT '->' $WANPORT >>/BitComet/DockerStun.log
echo $WANPORT $LANPORT >/BitComet/DockerStunPort_$L4PROTO

[[ $StunMode =~ ^(tcp|udp)$ ]] && {
	echo 当前为传统模式，更新 BitComet 监听端口 | LOG
	/files/BitComet/bin/bitcometd --bt_port $WANPORT >/dev/null
}

[[ $StunMode =~ nft ]] && {
	echo 当前为改包模式，更新 nftables 规则 | LOG
}

# UPnP
[ "$StunUpnp" = 0 ] || {
	echo 已启用 UPnP | LOG
	ADD_UPNP() {
		[ $StunUpnpInterface ] && local StunUpnpInterface='-m '$StunUpnpInterface''
		[ $StunUpnpUrl ] && local StunUpnpUrl='-u '$StunUpnpUrl''
		[ $StunUpnpAddr ] || local StunUpnpAddr=@
		UPNP_START='upnpc '$StunUpnpArgs' '$StunUpnpInterface' '$StunUpnpUrl' -i -e "STUN BitComet Docker" -a '$StunUpnpAddr' '$UPNP_INPORT' '$UPNP_EXPORT' '$L4PROTO''
		[ $UPNP_TRY ] || {
			echo 本次 UPnP 执行命令 | LOG
			echo $UPNP_START | LOG
		}
		UPNP_RES=$(eval $UPNP_START 2>&1)
		UPNP_FLAG=$?
		[ $UPNP_FLAG = 0 ] && echo 更新 UPnP 规则成功 | LOG
	}
	[ -f /BitComet/DockerStunUpnpInterface ] && export StunUpnpInterface='br-lan'
	UPNP_EXPORT=$LANPORT
	[[ $StunMode =~ ^(tcp|udp)$ ]] && UPNP_INPORT=$WANPORT
	[[ $StunMode =~ nft ]] && UPNP_INPORT=$LANPORT
	echo 本次 UPnP 规则：转发 外部端口 $UPNP_EXPORT/$L4PROTO 至 内部端口 $UPNP_INPORT/$L4PROTO | LOG
	ADD_UPNP
	[ $UPNP_FLAG = 1 ] && [[ $UPNP_RES == *'No IGD UPnP Device found on the network'* ]] && [ "$StunUpnpInterface" != '-m br-lan' ] && \
	[ $(ls /sys/class/net | grep ^br-lan$) ] && {
		echo 未找到 IGD UPnP 设备，尝试使用 br-lan 接口 | LOG
		export StunUpnpInterface='br-lan'
		ADD_UPNP
		[[ $UPNP_FLAG =~ ^[02]$ ]] && echo br-lan >/BitComet/DockerStunUpnpInterface
	}
	# awk '{print$2}' /proc/net/$L4PROTO | grep -qi ":$(printf '%04x' $LANPORT)" && \
	[ $UPNP_FLAG = 2 ] && [[ $UPNP_RES == *'ConflictWithOtherMechanisms'* ]] && {
		echo 当前 IGD UPnP 设备启用了端口占用检测，尝试使用兼容模式 | LOG
		>/BitComet/DockerStunUpnpConflict
		[ $L4PROTO = tcp ] && STUN_START=$(ps x | grep 'natmap ' | grep -vE 'grep|-u' | grep -o "natmap.*-b $LANPORT.*")
		[ $L4PROTO = udp ] && STUN_START=$(ps x | grep 'natmap ' | grep -e '-u' | grep -v grep | grep -o "natmap.*-b $LANPORT.*")
		echo 终止 NATMap 进程并等待端口释放，最大限时 300 秒 | LOG
		kill $(ps x | grep "$STUN_START" | grep -v grep | awk '{print$1}')
		for SERVER in $(cat /BitComet/DockerStunServers.txt); do
			IP=$(echo $SERVER | awk -F : '{print$1}')
			PORT=$(echo $SERVER | awk -F : '{print$2}')
			echo "000100002112a442$(head -c 12 /dev/urandom | xxd -p)" | xxd -r -p | timeout 2 socat - ${L4PROTO}4:$IP:$PORT,reuseport,sourceport=$LANPORT >/dev/null 2>&1
			sleep 25
		done &
		UPNP_KEEPALIVE_PID=$!
		# sleep $(expr $(awk '{print$2,$6}' /proc/net/$L4PROTO | grep -i ":$(printf '%04x' $LANPORT)" | awk -F : '{print$3}' | awk '{printf"%d\n",strtonum("0x"$0),$0}' | sort -n | tail -1) / $(getconf CLK_TCK))
		timeout 300 bash -c "while awk '{print\$2}' /proc/net/$L4PROTO | grep -qi ":$(printf '%04x' $LANPORT)"; do sleep 1; done"
		if [ $? = 0 ]; then
			echo 端口释放成功，尝试更新 UPnP 规则 | LOG
		else
			echo 端口释放失败，仍继续尝试更新 UPnP 规则 | LOG
		fi
		until [ $UPNP_FLAG = 0 ] || [ "$UPNP_TRY" = 5 ]; do
			let UPNP_TRY++
			echo UPnP 兼容模式第 $UPNP_TRY 次尝试，最多 5 次
			ADD_UPNP
			[ $UPNP_FLAG = 0 ] || [ $UPNP_TRY = 5 ] || sleep 15
		done
		kill $UPNP_KEEPALIVE_PID >/dev/null 2>&1
		echo 重新执行 NATMap | LOG
		eval $STUN_START
	}
	[ $UPNP_FLAG = 1 ] && echo 更新 UPnP 规则失败，错误信息如下 | LOG && echo "$UPNP_RES" | head -1 | LOG
	[ $UPNP_FLAG = 2 ] && echo 更新 UPnP 规则失败，错误信息如下 | LOG && echo "$UPNP_RES" | tail -1 | LOG
}

# exit 0