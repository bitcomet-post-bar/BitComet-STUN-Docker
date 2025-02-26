#!/bin/bash

# 初始化变量
L4PROTO=$1
[ $StunInterval ] || export StunInterval=25
[ $StunInterface ] && \
if [[ "$StunInterface" =~ ([0-9]{1,3}\.){3}[0-9]{1,3} ]]; then
	StunInterface=',bind='$StunInterface''
else
	StunInterface=',interface='$StunInterface''
fi

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
		local IP=$(echo $SERVER | awk -F : '{print$1}')
		local PORT=$(echo $SERVER | awk -F : '{print$2}')
		local RES=$(echo "000100002112a442$(head -c 12 /dev/urandom | xxd -p)" | xxd -r -p | eval timeout 2 socat - ${L4PROTO}4:$IP:$PORT,reuseport,sourceport=$1$StunInterface 2>&1 | xxd -p -c 64)
		echo $RES | tr -d ' ' | grep -q 4164647265737320616c726561647920696e20757365 && {
			[ "$BC_BT_PORT_SHUF" = 10 ] && {
				LOG 端口冲突次数达到上限，停止容器
				kill -15 1
				exit
			}
			LOG 检测到端口冲突，修改 BitComet BT 端口
			while
				awk '{print$2,$4}' /proc/net/tcp /proc/net/tcp6 | grep 0A | grep -qiE '(0{8}|0{32}):'$(printf '%04x' $BITCOMET_BT_PORT)'' || \
				awk '{print$2,$4}' /proc/net/udp /proc/net/udp6 | grep 07 | grep -qiE '(0{8}|0{32}):'$(printf '%04x' $BITCOMET_BT_PORT)'' || \
				echo $BITCOMET_BT_PORT | grep -qE '^('$BITCOMET_WEBUI_PORT'|'$PBH_WEBUI_PORT'|'$StunMitmEnPort'|'$StunMitmDePort')$'
			do
				export BITCOMET_BT_PORT=$(shuf -i 10000-65535 -n 1)
				let BC_BT_PORT_SHUF++
			done
			/files/BitComet/bin/bitcometd --bt_port $BITCOMET_BT_PORT >/dev/null
			break
		}
		local HEX=$(echo $RES | grep -oE '002000080001.{12}')
		if [ $HEX ]; then
			[ ${HEX:12:4} = "${STUN_HEX:12:4}" ] && break
			STUN_HEX=$HEX
			STUN_IP=$(printf '%d.%d.%d.%d\n' $(printf '%x\n' $((0x${HEX:16:8}^0x2112a442)) | sed 's/../0x& /g'))
			STUN_PORT=$((0x${HEX:12:4}^0x2112))
			stun_exec.sh $STUN_IP $STUN_PORT $StunBindPort $L4PROTO &
			break
		else
			LOG STUN 服务器 $SERVER 不可用，后续排除
			sed '/^'$SERVER'$/d' -i /tmp/StunServers_$L4PROTO.txt
		fi
	done
}

# 初始化
[ -s /tmp/StunServers_$L4PROTO.txt ] || sort -R StunServers.txt >/tmp/StunServers_$L4PROTO.txt

while :; do
	[ -s /tmp/StunServers_$L4PROTO.txt ] || UPDATE_SERVERS
	GET_NAT $StunBindPort
	sleep $StunInterval
done
