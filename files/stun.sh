#!/bin/bash

# 初始化变量
L4PROTO=$1
[ $StunInterval ] || export StunInterval=25

# 定义日志函数
LOG() { echo "$*" | tee -a /BitComet/DockerLogs.log ;}

# 防止脚本重复运行
pkill -Af "$0 $*"

# 更新 HTTP 服务器
UPDATE_HTTP() {
	LOG 已启用 TCP 通道，更新 HTTP 服务器列表，最多等待 15 秒
	echo -ne "GET /topsite_ip.txt HTTP/1.1\r\nHost: oniicyan.pages.dev\r\nConnection: close\r\n\r\n" | \
	timeout 15 openssl s_client -connect oniicyan.pages.dev:443 -quiet 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' >/tmp/SiteList.txt
	if [ -s /tmp/SiteList.txt ]; then
		LOG 更新 HTTP 服务器列表成功
		mv -f /tmp/SiteList.txt SiteList.txt
	else
		LOG 更新 HTTP 服务器列表失败，本次跳过
		[ -f SiteList.txt ] || cp /files/SiteList.txt SiteList.txt
	fi
	sort -R SiteList.txt >/tmp/SiteList_tcp.txt
	LOG 已加载 $(wc -l </tmp/SiteList_tcp.txt) 个 HTTP 服务器
}

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
		local RES=$(echo "000100002112a442$(head -c 12 /dev/urandom | xxd -p)" | xxd -r -p | eval runuser -u socat -- timeout 2 socat - ${L4PROTO}4:$SERVER,reuseport,sourceport=$STUN_BIND_PORT$STUN_IFACE 2>&1 | xxd -p -c 0 | grep -oE '002000080001.{12}')
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
			break
		}
		unset STUN_PORT_FLAG
		[ $HEX ] && {
			[ ${HEX:12:4} = "${STUN_HEX:12:4}" ] && break
			[ $(($(date +%s)-$STUN_TIME)) -lt $(($StunInterval/$STUN_TIME_FLAG*2)) ] && {
				LOG 穿透通道保持时间低于 $(($StunInterval/$STUN_TIME_FLAG*2)) 秒（两次心跳间隔）
				let STUN_TIME_FLAG++
				LOG 降低 STUN 心跳间隔，当前为 $(($StunInterval/$STUN_TIME_FLAG)) 秒
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
			stun_exec.sh $STUN_IP $STUN_PORT $STUN_BIND_PORT $L4PROTO &
			break
		}
		LOG STUN 服务器 $SERVER 不可用，后续排除
		sed '/^'$SERVER'$/d' -i /tmp/StunServers_$L4PROTO.txt
	done
}

# 穿透通道保活
KEEPALIVE() {
	for SERVER in $(cat /tmp/SiteList_$L4PROTO.txt); do
		local RES=$(echo -ne "HEAD / HTTP/1.1\r\nHost: $SERVER\r\nConnection: keep-alive\r\n\r\n" | eval runuser -u socat -- timeout 2 socat - tcp4:$SERVER:80,reuseport,sourceport=$STUN_BIND_PORT$STUN_IFACE 2>&1)
		echo "$RES" | grep -q HTTP && break
		let STUN_HTTP_FLAG++
		sed '/^'$SERVER'$/d' -i /tmp/SiteList_$L4PROTO.txt
		[ $STUN_HTTP_FLAG -ge 10 ] && LOG HTTP 保活连续失败 10 次，本次跳过 && break
	done
	unset STUN_HTTP_FLAG
}

# 初始化 STUN
[ -s /tmp/StunServers_$L4PROTO.txt ] || sort -R StunServers.txt >/tmp/StunServers_$L4PROTO.txt
STUN_TIME=0
STUN_TIME_FLAG=1
LOG 当前 STUN 心跳间隔为 $StunInterval 秒
[ $StunInterface ] && LOG 当前 STUN 绑定接口为 $StunInterface
if [[ $StunMode =~ nft ]]; then
	STUN_BIND_PORT=$(shuf -i 1024-65535 -n 1)
	NFTNAME=Docker_BitComet_$STUN_ORIG_PORT
	[ $STUN_IFACE_IP ] && APPRULE='ip saddr '$StunInterface''
	[ $STUN_IFACE_IP ] || APPRULE='fib daddr type != local'
	[ $STUN_IFACE_IF ] && OIFNAME='oifname '$StunInterface''
	nft add table ip STUN
	nft add chain ip STUN HOOK { type nat hook output priority dstnat \; }
	for HANDLE in $(nft -as list chain ip STUN HOOK | grep \"$NFTNAME\" | grep $L4PROTO | awk '{print$NF}'); do nft delete rule ip STUN HOOK handle $HANDLE; done
	nft insert rule ip STUN HOOK skuid 50080 $OIFNAME $APPRULE $L4PROTO sport $STUN_BIND_PORT counter ct mark set 0x50080 comment $NFTNAME
	nft add chain ip STUN SNAT { type nat hook postrouting priority srcnat - 5 \; }
	for HANDLE in $(nft -as list chain ip STUN SNAT | grep \"$NFTNAME\" | grep $L4PROTO | awk '{print$NF}'); do nft delete rule ip STUN SNAT handle $HANDLE; done
	nft insert rule ip STUN SNAT meta l4proto $L4PROTO ct mark 0x50080 counter snat to :$STUN_ORIG_PORT comment $NFTNAME
else
	STUN_BIND_PORT=$STUN_ORIG_PORT
fi

# 执行 STUN
while :; do
	[ -s /tmp/StunServers_$L4PROTO.txt ] || UPDATE_STUN
	[ $L4PROTO = tcp ] && [ ! -s /tmp/SiteList_tcp.txt ] && UPDATE_HTTP
	GET_NAT
	[ $L4PROTO = tcp ] && KEEPALIVE
	sleep $(($StunInterval/$STUN_TIME_FLAG))
done
