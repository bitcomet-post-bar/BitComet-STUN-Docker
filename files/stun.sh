#!/bin/bash

# 初始化变量
L4PROTO=$1
[ $StunInterval ] || export StunInterval=25

# 定义日志函数
LOG() { echo "$*" | tee -a /BitComet/DockerLogs.log ;}

# 防止脚本重复运行
pkill -Af $0.*$L4PROTO

# 更新 STUN 服务器
UPDATE_STUN() {
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
	LOG 已加载 $(wc -l </tmp/StunServers_$L4PROTO.txt) 个 STUN 服务器
}

# 穿透通道检测
GET_NAT() {
	for SERVER in $(cat /tmp/StunServers_$L4PROTO.txt); do
		local RES=$(echo "000100002112a442$(head -c 12 /dev/urandom | xxd -p)" | xxd -r -p | eval runuser -u socat -- socat - ${L4PROTO}4:$SERVER,connect-timeout=2,reuseport,sourceport=$STUN_BIND_PORT$STUN_IFACE 2>&1 | xxd -p -c 0)
		local HEX=$(echo $RES | grep -oE '002000080001.{12}')
		echo $RES | grep -q 4164647265737320616c726561647920696e20757365 && {
			let STUN_PORT_FLAG++
			[ $STUN_PORT_FLAG -ge 10 ] && {
				LOG 连续 10 次端口被占用，暂停穿透 3600 秒
				sleep 3600
				unset STUN_PORT_FLAG
				break
			}
			LOG 穿透通道本地端口被占用，跳过 $STUN_PORT_FLAG 次
			[[ $StunMode =~ nft ]] && export STUN_BIND_PORT=$(shuf -i 1024-65535 -n 1)
			break
		}
		unset STUN_PORT_FLAG
		[ $HEX ] && {
			[ ${HEX:12:4} = "${STUN_HEX:12:4}" ] && break
			[ $(($(date +%s)-$STUN_TIME)) -lt $(($StunInterval/$STUN_TIME_FLAG*3)) ] && {
				LOG 穿透通道保持时间低于 $(($StunInterval/$STUN_TIME_FLAG*3)) 秒（三次心跳间隔）
				let STUN_TIME_FLAG++
				LOG 缩短 STUN 心跳间隔，当前为 $(($StunInterval/$STUN_TIME_FLAG)) 秒
				[ $STUN_TIME_FLAG -ge 10 ] && {
					LOG 连续 10 次保持时间过短，暂停穿透 3600 秒
					sleep 3600
					STUN_TIME=0
					STUN_TIME_FLAG=1
					break
				}
			}
			STUN_HEX=$HEX
			STUN_IP=$(printf '%d.%d.%d.%d\n' $(printf '%x\n' $((0x${HEX:16:8}^0x2112a442)) | sed 's/../0x& /g'))
			STUN_PORT=$((0x${HEX:12:4}^0x2112))
			STUN_TIME=$(date +%s)
			pkill -f stun_upnp_keep.sh
			stun_exec.sh $STUN_IP $STUN_PORT $STUN_BIND_PORT $L4PROTO &
			break
		}
		# LOG STUN 服务器 $SERVER 不可用，后续排除
		echo $RES | grep -q 20436f6e6e656374696f6e2074696d6564206f7574 && sed '/^'$SERVER'$/d' -i /tmp/StunServers_$L4PROTO.txt
	done
}

# 初始化 STUN
[ -s /tmp/StunServers_$L4PROTO.txt ] || sort -R StunServers.txt >/tmp/StunServers_$L4PROTO.txt
STUN_TIME=0
STUN_TIME_FLAG=1
LOG 当前 STUN 心跳间隔为 $StunInterval 秒
[ $StunInterface ] && LOG 当前 STUN 绑定接口为 $StunInterface
if [[ $StunMode =~ nft ]]; then
	export STUN_BIND_PORT=$(shuf -i 1024-65535 -n 1)
	NFTNAME=Docker_BitComet_$STUN_ORIG_PORT
	[ $STUN_IFACE_IP ] && APPRULE='ip saddr '$StunInterface''
	[ $STUN_IFACE_IP ] || APPRULE='fib daddr type != local'
	[ $STUN_IFACE_IF ] && OIFNAME='oifname '$StunInterface''
	nft add table ip STUN
	nft add chain ip STUN NAT_OUTPUT { type nat hook output priority dstnat \; }
	for HANDLE in $(nft -as list chain ip STUN NAT_OUTPUT | grep \"${NFTNAME}_snat\" | grep $L4PROTO | awk '{print$NF}'); do nft delete rule ip STUN NAT_OUTPUT handle $HANDLE; done
	nft insert rule ip STUN NAT_OUTPUT skuid 50080 $OIFNAME $APPRULE meta l4proto $L4PROTO counter ct mark set 0x50080 comment ${NFTNAME}_snat
	nft add chain ip STUN NAT_POSTROUTING { type nat hook postrouting priority srcnat - 5 \; }
	for HANDLE in $(nft -as list chain ip STUN NAT_POSTROUTING | grep \"${NFTNAME}_snat\" | grep $L4PROTO | awk '{print$NF}'); do nft delete rule ip STUN NAT_POSTROUTING handle $HANDLE; done
	nft insert rule ip STUN NAT_POSTROUTING meta l4proto $L4PROTO ct mark 0x50080 counter snat to :$STUN_ORIG_PORT comment ${NFTNAME}_snat
else
	export STUN_BIND_PORT=$STUN_ORIG_PORT
fi

# 捕获暂停信号
trap 'sleep '$(($StunInterval*3))'' SIGUSR1

# 循环执行 STUN
while :; do
	[ -s /tmp/StunServers_$L4PROTO.txt ] || UPDATE_STUN
	GET_NAT
	sleep $(($StunInterval/$STUN_TIME_FLAG))
done
