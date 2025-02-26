#!/bin/bash

# 初始化变量
L4PROTO=$1
[ $StunInterval ] || export StunInterval=25

# 定义日志函数
LOG() { echo "$*" | tee -a /BitComet/DockerLogs.log ;}

# 防止脚本重复运行
pkill -Af "$0 $*"

# 更新服务器
UPDATE_SERVERS() {
	LOG 更新 STUN 服务器列表，最多等待 15 秒
	echo -ne "GET /stun_servers_ipv4_rst.txt HTTP/1.1\r\nHost: oniicyan.pages.dev\r\nConnection: close\r\n\r\n" | \
	timeout 15 openssl s_client -connect oniicyan.pages.dev:443 -quiet 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{1,5}' >/tmp/StunServers.txt
	if [ -s /tmp/StunServers.txt ]; then
		LOG 更新 STUN 服务器列表成功
		mv -f /tmp/StunServers.txt StunServers.txt
	else
		LOG 更新 STUN 服务器列表失败，本次跳过
		[ -f StunServers.txt ] || cp /files/StunServers.txt StunServers.txt
	fi
	sort -R StunServers.txt >/tmp/StunServers_$L4PROTO.txt
	LOG 已获取 $(wc -l </tmp/StunServers_$L4PROTO.txt) 个 STUN 服务器
}

# 检测穿透通道
GET_NAT() {
	for SERVER in $(cat /tmp/StunServers_$L4PROTO.txt); do
		pgrep -f socat.+$L4PROTO.+$L4PROTO >/dev/null || {
			LOG socat 监听端口 $STUN_BIND_PORT/$L4PROTO，使用 STUN 服务器 $SERVER
			socat ${L4PROTO}4-listen:$STUN_BIND_PORT,reuseport,fork ${L4PROTO}4:$SERVER,reuseport,sourceport=$STUN_BIND_PORT$STUN_IFACE 2>/tmp/socat_$L4PROTO.txt &
			grep -q 'Address already in use' /tmp/socat_$L4PROTO.txt && {
				if [[ $StunMode =~ nft ]]; then
					let STUN_PORT_FLAG++
					[ $STUN_PORT_FLAG -ge 10 ] && LOG 监听端口失败次数达到上限，停止容器 && kill 1 && exit
					LOG 监听端口失败，尝试使用其他端口
					pkill -9 -f socat.+$L4PROTO.+$L4PROTO
					STUN_BIND_PORT=$(shuf -i 1024-65535 -n 1)
					for HANDLE in $(nft -as list chain ip STUN SNAT | grep \"$NFTNAME\" | grep $L4PROTO | awk '{print$NF}'); do nft delete rule ip STUN SNAT handle $HANDLE; done
					nft insert rule ip STUN SNAT skuid 50080 $OIFNAME $APPRULE $L4PROTO sport $STUN_BIND_PORT counter snat to :$STUN_ORIG_PORT comment $NFTNAME
					continue
				else
					LOG 监听端口失败，停止容器 && kill 1 && exit
				fi
			}
			STUN_PORT_FLAG=0
		}
		local HEX=$(echo "000100002112a442$(head -c 12 /dev/urandom | xxd -p)" | xxd -r -p | eval timeout 2 socat - ${L4PROTO}4:127.0.0.1:$STUN_BIND_PORT | xxd -p -c 0 | grep -oE '002000080001.{12}')
		if [ $HEX ]; then
			[ ${HEX:12:4} = "${STUN_HEX:12:4}" ] && break
			if [ $(($(date +%s)-$STUN_TIME)) -lt $(($StunInterval*2)) ]; then
				let STUN_TIME_FLAG++
				LOG 穿透通道保持时间低于 $(($StunInterval*2)) 秒（两次心跳间隔）
				[ $STUN_TIME_FLAG -ge 10 ] && {
					LOG 连续 10 次保持时间过短，暂停穿透 3600 秒
					sleep 3600
					STUN_TIME=0
					STUN_TIME_FLAG=0
					break
				}
			else
				STUN_TIME_FLAG=0
			fi
			STUN_HEX=$HEX
			STUN_IP=$(printf '%d.%d.%d.%d\n' $(printf '%x\n' $((0x${HEX:16:8}^0x2112a442)) | sed 's/../0x& /g'))
			STUN_PORT=$((0x${HEX:12:4}^0x2112))
			STUN_TIME=$(date +%s)
			stun_exec.sh $STUN_IP $STUN_PORT $STUN_BIND_PORT $L4PROTO &
			break
		else
			LOG STUN 服务器 $SERVER 不可用，后续排除
			sed '/^'$SERVER'$/d' -i /tmp/StunServers_$L4PROTO.txt
		fi
	done
}

# 初始化 STUN
[ -s /tmp/StunServers_$L4PROTO.txt ] || sort -R StunServers.txt >/tmp/StunServers_$L4PROTO.txt
STUN_TIME=0
LOG 当前 STUN 心跳间隔为 $StunInterval 秒
[ $StunInterface ] && LOG 当前 STUN 绑定接口为 $StunInterface
if [[ $StunMode =~ nft ]]; then
	STUN_BIND_PORT=$(shuf -i 1024-65535 -n 1)
	NFTNAME=Docker_BitComet_$STUN_ORIG_PORT
	[ $STUN_IFACE_IP ] && APPRULE='ip saddr '$StunInterface''
	[ $STUN_IFACE_IP ] || APPRULE='ip saddr != 127.0.0.1'
	[ $STUN_IFACE_IF ] && OIFNAME='oifname '$StunInterface''
	nft add chain ip STUN SNAT { type nat hook postrouting priority srcnat + 5 \; }
	nft insert rule ip STUN SNAT skuid 50080 $OIFNAME $APPRULE $L4PROTO sport $STUN_BIND_PORT counter snat to :$STUN_ORIG_PORT comment $NFTNAME
else
	STUN_BIND_PORT=$STUN_ORIG_PORT
fi

# 执行 STUN
while :; do
	[ -s /tmp/StunServers_$L4PROTO.txt ] || UPDATE_SERVERS
	GET_NAT
	sleep $StunInterval
done
