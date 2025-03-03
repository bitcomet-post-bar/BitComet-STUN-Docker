#!/bin/bash

# 初始化变量
[ $BITCOMET_WEBUI_USERNAME ] && export WEBUI_USERNAME=$BITCOMET_WEBUI_USERNAME
[ $BITCOMET_WEBUI_PASSWORD ] && export WEBUI_PASSWORD=$BITCOMET_WEBUI_PASSWORD
HOSTIP=$(awk '/32 host/{print f}{f=$2}' /proc/net/fib_trie | grep -v 127.0.0.1 | sort | uniq)

# 清理文件
rm -f /tmp/*.txt
rm -f StunPort* StunUpnpInterface StunUpnpMiss StunUpnpConflict* StunNftables* StunHttpsTrackers

# 初始化日志函数
LOG() { echo "$*" | tee -a /BitComet/DockerLogs.log ;}

echo 开始执行 BitComet 贴吧修改版 | tee /tmp/DockerLogs.log

# 初始化配置目录
for DIR in /BitComet /PeerBanHelper; do
	if ! mount | grep -q ' '$DIR' '; then
		echo $DIR 目录未挂载 | tee -a /tmp/DockerLogs.log
		DIR_CFG_FLAG=1
		mkdir $DIR
	fi
done
chmod 775 /BitComet
chmod 775 /PeerBanHelper
mv -f /BitComet/DockerLogs.log /BitComet/DockerLogs.old 2>/dev/null
mv -f /tmp/DockerLogs.log /BitComet/DockerLogs.log
[ $DIR_CFG_FLAG ] && LOG 应用程序配置及数据保存到容器层，重启后可能会丢失

# 初始化 BitComet 配置文件
BC_CFG=/BitComet/BitComet.xml
[ -f $BC_CFG ] || {
	LOG BitComet 配置文件不存在，执行初始化
	cp /files/BitComet.xml $BC_CFG
}
grep DefaultDownloadPath $BC_CFG | grep -q /Downloads || sed 's,<Settings>,<Settings><DefaultDownloadPath>/Downloads</DefaultDownloadPath>,' -i $BC_CFG
grep EnableUPnP $BC_CFG | grep -q false || sed 's,<Settings>,<Settings><EnableUPnP>false</EnableUPnP>,' -i $BC_CFG
grep EnableTorrentShare $BC_CFG | grep -q false || sed 's,<Settings>,<Settings><EnableTorrentShare>false</EnableTorrentShare>,' -i $BC_CFG

# 初始化 BitComet 保存位置
if mount | grep -q ' /Downloads '; then
	LOG /Downloads 目录已挂载
else
	LOG /Downloads 目录未挂载，默认保存位置在容器层，重启后可能会丢失
	BC_DL_FLAG=1
	mkdir /Downloads
	
fi
chmod 775 /Downloads
BC_DL_REX='/Downloads|/BitComet|/PeerBanHelper|/tmp|/etc/resolv.conf|/etc/hostname|/etc/hosts'
BC_DL_DIR=$(mount | grep -E '^/' | grep -vE ' ('$BC_DL_REX') ' | awk '{print$3}')
if [ $BC_DL_DIR ]; then
	LOG 以下目录将作为 BitComet 的自定义保存位置
	for DIR in $BC_DL_DIR; do
		LOG $DIR
		chmod 775 $DIR
	done
	sed 's,<Settings>,<Settings><DirCandidate>'$(echo $BC_DL_DIR | sed 's, /,|/,')'</DirCandidate>,' -i $BC_CFG
else
	[ $BC_DL_FLAG ] && LOG 未挂载任何自定义下载目录
fi

# 初始化 BitComet WebUI 用户名与密码
[ $WEBUI_USERNAME ] || export WEBUI_USERNAME=$(grep WebInterfaceUsername $BC_CFG | grep -oE '>.*<' | tr -d '><')
[ $WEBUI_PASSWORD ] || export WEBUI_PASSWORD=$(grep WebInterfacePassword $BC_CFG | grep -oE '>.*<' | tr -d '><')
[ "$WEBUI_USERNAME" = test ] && {
	unset WEBUI_USERNAME
	echo 禁止使用用户名 test，已清除
}
[ "$WEBUI_PASSWORD" = test ] && {
	unset WEBUI_PASSWORD
	echo 禁止使用密码 test，已清除
}
[ $WEBUI_USERNAME ] || {
	export WEBUI_USERNAME=$(base64 /proc/sys/kernel/random/uuid | cut -c -8)
	LOG BitComet WebUI 用户名未指定，随机生成以下 8 位用户名
	LOG $WEBUI_USERNAME
}
[ $WEBUI_PASSWORD ] || {
	export WEBUI_PASSWORD=$(base64 /proc/sys/kernel/random/uuid | cut -c -16)
	LOG BitComet WebUI 密码未指定，随机生成以下 16 位密码
	LOG $WEBUI_PASSWORD
}
>/BitComet/Secrect
echo WebInterfaceUsername: $WEBUI_USERNAME >>/BitComet/Secrect
echo WebInterfacePassword: $WEBUI_PASSWORD >>/BitComet/Secrect
LOG BitComet WebUI 用户名与密码已保存至 /BitComet/Secrect

# 初始化 BitComet WebUI 端口
[ $BITCOMET_WEBUI_PORT ] || export BITCOMET_WEBUI_PORT=$(grep WebInterfacePort $BC_CFG | grep -oE '>.*<' | tr -d '><')
if [ $BITCOMET_WEBUI_PORT ]; then
	if [[ $BITCOMET_WEBUI_PORT =~ ^[0-9]+$ ]] && [ $BITCOMET_WEBUI_PORT -le 65535 ]; then
		[ $BITCOMET_WEBUI_PORT -ge 1024 ] || LOG BitComet WebUI 端口指定为 1024 以下，可能无法监听
		BC_WEBUI_PORT_ORIG=$BITCOMET_WEBUI_PORT
	else
		LOG BitComet WebUI 端口指定错误，仅接受 65535 以下数字，重新分配
		export BITCOMET_WEBUI_PORT=8080
	fi
else
	LOG BitComet WebUI 端口未指定，自动分配
	export BITCOMET_WEBUI_PORT=8080
fi
while (>/dev/tcp/0.0.0.0/$BITCOMET_WEBUI_PORT) 2>/dev/null || echo $BITCOMET_WEBUI_PORT | grep -qE '^('$BITCOMET_BT_PORT'|'$PBH_WEBUI_PORT'|'$StunMitmEnPort'|'$StunMitmDePort')$' ; do
	export BITCOMET_WEBUI_PORT=$(shuf -i 1024-65535 -n 1)
	BC_WEBUI_PORT_SHUF=1
done
[ $BC_WEBUI_PORT_ORIG ] &&[ $BC_WEBUI_PORT_SHUF ] && LOG BitComet WebUI 端口 $BC_WEBUI_PORT_ORIG 被占用，已重新分配

# 初始化 PeerBanHelper 配置文件
PBH_CFG=/PeerBanHelper/data/config/config.yml
if [ -f $PBH_CFG ]; then
	[ $(sed -n '/^server:/,/^[^ ]/{/^ \+address:/p}' $PBH_CFG | awk -F : '{print$2}') ] || \
	LOG PeerBanHelper 配置文件不正确，执行初始化
	cp -f /files/PeerBanHelper/config.yml $PBH_CFG
else
	LOG PeerBanHelper 配置文件不存在，执行初始化
	mkdir -p /PeerBanHelper/data/config
	cp /files/PeerBanHelper/config.yml $PBH_CFG
fi

# 初始化 PeerBanHelper WebUI Token
[ $PBH_WEBUI_TOKEN ] || export PBH_WEBUI_TOKEN=$(sed -n '/^server:/,/^[^ ]/{/^ \+token:/p}' $PBH_CFG | awk -F : '{print$2}')
if [ ! $PBH_WEBUI_TOKEN ]; then
	export PBH_WEBUI_TOKEN=$(cat /proc/sys/kernel/random/uuid)
	LOG PeerBanHelper WebUI Token 未指定，随机生成以下 Token
	LOG $PBH_WEBUI_TOKEN
	if [ "$(sed -n '/^server:/,/^[^ ]/{/^ \+token:/p}' $PBH_CFG)" ]; then
		sed '/^server:/,/^[^ ]/{/^ \+token:/{s/token:.*/token: '$PBH_WEBUI_TOKEN'/}}' -i $PBH_CFG
	else
		PBH_TOKEN_STR=$(sed -n '/^server:/,/^[^ ]/{/^ \+address:/{s/address:.*/token: '$PBH_WEBUI_TOKEN'/p}}' $PBH_CFG)
		sed '/^server:/a\'"$PBH_TOKEN_STR"'' -i $PBH_CFG
	fi
fi
echo $PBH_WEBUI_TOKEN >/PeerBanHelper/Secrect
LOG PeerBanHelper WebUI Token 已保存至 /PeerBanHelper/Secrect

# 初始化 PeerBanHelper WebUI 端口
[ $PBH_WEBUI_PORT ] || export PBH_WEBUI_PORT=$(sed -n '/^server:/,/^[^ ]/{/^ \+http:/p}' $PBH_CFG | awk -F : '{print$2}' | tr -d ' "')
if [ $PBH_WEBUI_PORT ]; then
	if [[ $PBH_WEBUI_PORT =~ ^[0-9]+$ ]] && [ $PBH_WEBUI_PORT -le 65535 ]; then
		[ $PBH_WEBUI_PORT -ge 1024 ] || LOG PeerBanHelper WebUI 端口指定为 1024 以下，可能无法监听
		PBH_PORT_ORIG=$PBH_WEBUI_PORT
	else
		LOG PeerBanHelper WebUI 端口指定错误，仅接受 65535 以下数字，重新分配
		export PBH_WEBUI_PORT=9898
	fi
else
	LOG PeerBanHelper WebUI 端口未指定，自动分配
	export PBH_WEBUI_PORT=9898
fi
while (>/dev/tcp/0.0.0.0/$PBH_WEBUI_PORT) 2>/dev/null || echo $PBH_WEBUI_PORT | grep -qE '^('$BITCOMET_WEBUI_PORT'|'$BITCOMET_BT_PORT'|'$StunMitmEnPort'|'$StunMitmDePort')$' ; do
	export PBH_WEBUI_PORT=$(shuf -i 1024-65535 -n 1)
	PBH_PORT_SHUF=1
done
[ $PBH_PORT_ORIG ] && [ $PBH_PORT_SHUF ] && LOG PeerBanHelper WebUI 端口 $PBH_PORT_ORIG 被占用，已重新分配
[ $PBH_WEBUI_PORT != "$PBH_PORT_ORIG" ] && \
if [ "$(sed -n '/^server:/,/^[^ ]/{/^ \+http:/p}' $PBH_CFG)" ]; then
	sed '/^server:/,/^[^ ]/{/^ \+http:/{s/http:.*/http: '$PBH_WEBUI_PORT'/}}' -i $PBH_CFG
else
	PBH_PORT_STR=$(sed -n '/^server:/,/^[^ ]/{/^ \+address:/{s/address:.*/http: '$PBH_WEBUI_PORT'/p}}' $PBH_CFG)
	sed '/^server:/a\'"$PBH_PORT_STR"'' -i $PBH_CFG
fi

# 初始化 PeerBanHelper 下载器
grep -q '^client: *$' $PBH_CFG || echo client: >>$PBH_CFG
[ $(sed -n '/^client:/,/^[^ ]/{/^ \+BitCometDocker:/p}' $PBH_CFG) ] || {
	LOG PeerBanHelper 未配置本机 BitComet，执行初始化
	cat >/tmp/PBH_CLIENT_STR <<EOF
  BitCometDocker:
    type: bitcomet
    endpoint: http://127.0.0.1:$BITCOMET_WEBUI_PORT
    username: $WEBUI_USERNAME
    password: $WEBUI_PASSWORD
    http-version: HTTP_2
    increment-ban: true
    verify-ssl: false
EOF
	sed '/^client:/r/tmp/PBH_CLIENT_STR' -i $PBH_CFG
}
PBH_CLIENT_SPACE=$(sed -n '/^client:/,/^[^ ]/{/^ \+BitCometDocker:/p}' $PBH_CFG | grep -o '^ \+')
[ "$(sed -n '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{/: \+'$WEBUI_USERNAME' *$/p}' $PBH_CFG)" ] || {
	LOG PeerBanHelper 配置中的本机 BitComet WebUI 用户名不正确，执行更正
	if [ "$(sed -n '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{/^ \+username:/p}' $PBH_CFG)" ]; then
		sed '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{s/username:.*/username: '$WEBUI_USERNAME'/}' -i $PBH_CFG
	else
		PBH_CLIENT_USERNAME_STR=$(sed -n '/^client:/,/^[^ ]/{/^ \+type:/{s/type:.*/username: '$WEBUI_USERNAME'/p}}' $PBH_CFG)
		sed '/^ \+BitCometDocker:/a\'"$PBH_CLIENT_USERNAME_STR"'' -i $PBH_CFG
	fi
}
[ "$(sed -n '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{/: \+'$WEBUI_PASSWORD' *$/p}' $PBH_CFG)" ] || {
	LOG PeerBanHelper 配置中的本机 BitComet WebUI 密码不正确，执行更正
	if [ "$(sed -n '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{/^ \+password:/p}' $PBH_CFG)" ]; then
		sed '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{s/password:.*/password: '$WEBUI_PASSWORD'/}' -i $PBH_CFG
	else
		PBH_CLIENT_PASSWORD_STR=$(sed -n '/^client:/,/^[^ ]/{/^ \+type:/{s/type:.*/password: '$WEBUI_PASSWORD'/p}}' $PBH_CFG)
		sed '/^ \+BitCometDocker:/a\'"$PBH_CLIENT_PASSWORD_STR"'' -i $PBH_CFG
	fi
}
[ $(sed -n '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{/endpoint/p}' $PBH_CFG | grep -oE :$BITCOMET_WEBUI_PORT/?$) ] || {
	LOG PeerBanHelper 配置中的本机 BitComet WebUI 地址不正确，执行更正
	if [ "$(sed -n '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{/^ \+endpoint:/p}' $PBH_CFG)" ]; then
		sed '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{s,endpoint:.*,endpoint: http://127.0.0.1:'$BITCOMET_WEBUI_PORT',}' -i $PBH_CFG
	else
		PBH_CLIENT_ENDPOINT_STR=$(sed -n '/^client:/,/^[^ ]/{/^ \+type:/{s,type:.*,endpoint: http://127.0.0.1:'$BITCOMET_WEBUI_PORT',p}}' $PBH_CFG)
		sed '/^ \+BitCometDocker:/a\'"$PBH_CLIENT_ENDPOINT_STR"'' -i $PBH_CFG
	fi
}

# 初始化 BitComet BT 端口
[ $BITCOMET_BT_PORT ] || [[ "$StunMode" =~ ^(tcp|udp)$ ]] || export BITCOMET_BT_PORT=$(grep ListenPort $BC_CFG | grep -oE '>.*<' | tr -d '><')
if [ $BITCOMET_BT_PORT ]; then
	if [[ $BITCOMET_BT_PORT =~ ^[0-9]+$ ]] && [ $BITCOMET_BT_PORT -le 65535 ]; then
		if [[ $StunMode =~ nft ]] && [ $BITCOMET_BT_PORT -lt 10000 ]; then
			LOG 改包模式下要求 BitComet BT 端口为 5 位数，重新分配
			BC_BT_PORT_FLAG=1
		else
			[ $BITCOMET_BT_PORT -ge 1024 ] || LOG BitComet BT 端口指定为 1024 以下，可能无法监听
			BC_BT_PORT_ORIG=$BITCOMET_BT_PORT
		fi
	else
		LOG BitComet BT 端口指定错误，仅接受 65535 以下数字，重新分配
		BC_BT_PORT_FLAG=1
	fi
else
	LOG BitComet BT 端口未指定，自动分配
	BC_BT_PORT_FLAG=1
fi
[ $BC_BT_PORT_FLAG ] && export BITCOMET_BT_PORT=56082
while
	awk '{print$2,$4}' /proc/net/tcp /proc/net/tcp6 | grep 0A | grep -qiE '(0{8}|0{32}):'$(printf '%04x' $BITCOMET_BT_PORT)'' || \
	awk '{print$2,$4}' /proc/net/udp /proc/net/udp6 | grep 07 | grep -qiE '(0{8}|0{32}):'$(printf '%04x' $BITCOMET_BT_PORT)'' || \
	echo $BITCOMET_BT_PORT | grep -qE '^('$BITCOMET_WEBUI_PORT'|'$PBH_WEBUI_PORT'|'$StunMitmEnPort'|'$StunMitmDePort')$'
do
	export BITCOMET_BT_PORT=$(shuf -i 10000-65535 -n 1)
	BC_BT_PORT_SHUF=1
done
[ $BC_BT_PORT_ORIG ] && [ $BC_BT_PORT_SHUF ] && LOG BitComet BT 端口 $BC_BT_PORT_ORIG 被占用，已重新分配
LOG BitComet BT 端口当前为 $BITCOMET_BT_PORT

# 检测是否 host 网络
[ $StunHost ] && {
	if [[ $StunHost =~ ^(0|1)$ ]]; then
		[ $StunHost = 0 ] && LOG 已指定非 host 网络，跳过检测
		[ $StunHost = 1 ] && LOG 已指定为 host 网络，跳过检测
	else
		LOG StunHost 仅接受 0 或 1，自动检测
		unset StunHost
	fi
}
[ $StunHost ] || {
	if [ -f /sys/class/net/eth0/address ] && grep -q ^02:42: /sys/class/net/eth0/address; then
		LOG 检测当前非 host 网络
		export StunHost=0
		for IP in $HOSTIP; do
			grep -q 02:42:$(echo $IP | awk -F . '{printf"%02x:%02x:%02x:%02x\n",$1,$2,$3,$4}') /sys/class/net/eth0/address && \
			STUN_HOST_FLAG=1
		done
		[ ! $STUN_HOST_FLAG ] && LOG eth0 的 MAC 地址格式不匹配，检测结果可能有误
	else
		LOG 检测当前为 host 网络
		export StunHost=1
	fi
}

# 更新 STUN 服务器列表
[ "$STUN" = 0 ] || {
	LOG 已启用 STUN，更新 STUN 服务器列表，最多等待 15 秒
	echo -ne "GET /stun_servers_ipv4_rst.txt HTTP/1.1\r\nHost: oniicyan.pages.dev\r\nConnection: close\r\n\r\n" | \
	timeout 15 openssl s_client -connect oniicyan.pages.dev:443 -quiet 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{1,5}' >/tmp/StunServers.txt
	if [ -s /tmp/StunServers.txt ]; then
		LOG 更新 STUN 服务器列表成功
		mv -f /tmp/StunServers.txt StunServers.txt
	else
		LOG 更新 STUN 服务器列表失败，本次跳过
		[ -f StunServers.txt ] || cp /files/StunServers.txt StunServers.txt
	fi
	LOG 已加载 $(wc -l <StunServers.txt) 个 STUN 服务器
}

# 检测 NAT 映射行为
GET_NAT() {
	LOG 使用 $1/$L4PROTO 进行第 $2 次绑定请求
	for SERVER in $(sort -R /tmp/StunServers_$L4PROTO.txt); do
		local HEX=$(echo "000100002112a442$(head -c 12 /dev/urandom | xxd -p)" | xxd -r -p | eval socat - ${L4PROTO}4:$SERVER,connect-timeout=2,reuseport,sourceport=$1$STUN_IFACE 2>/dev/null | xxd -p -c 0 | grep -oE '002000080001.{12}')
		if [ $HEX ]; then
			eval HEX$2=$HEX
			eval SERVER$2=$SERVER
			break
		else
			# LOG STUN 服务器 $SERVER 不可用，后续排除
			sed '/^'$SERVER'$/d' -i /tmp/StunServers_$L4PROTO.txt
		fi
	done
}
START_NAT() {
	local L4PROTO=$1
	LOG 检测 ${L4PROTO^^} 映射行为
	sort -R StunServers.txt >/tmp/StunServers_$L4PROTO.txt
	[ -s /tmp/StunServers_$L4PROTO.txt ] && GET_NAT $BITCOMET_BT_PORT 1
	[ -s /tmp/StunServers_$L4PROTO.txt ] && GET_NAT $BITCOMET_BT_PORT 2
	if [ $HEX1 ] && [ $HEX2 ]; then
		if [ ${HEX1:12:4} = ${HEX2:12:4} ]; then
			if [ $((0x${HEX1:12:4}^0x2112)) = $BITCOMET_BT_PORT ]; then
				LOG 内外端口一致，当前 ${L4PROTO^^} 为公网映射
				eval STUN_FLAG_${L4PROTO^^}=0
			else
				LOG 两次端口一致，当前 ${L4PROTO^^} 为锥形映射
				eval STUN_FLAG_${L4PROTO^^}=1
			fi
		else
			LOG 两次端口不同，进行额外检测
			[ -s /tmp/StunServers_$L4PROTO.txt ] && GET_NAT $BITCOMET_BT_PORT 3
			[ -s /tmp/StunServers_$L4PROTO.txt ] && GET_NAT $BITCOMET_BT_PORT 4
			if [[ "${HEX3:12:4}" =~ ^(${HEX1:12:4}|${HEX2:12:4}|${HEX4:12:4})$ ]] || [[ "${HEX4:12:4}" =~ ^(${HEX1:12:4}|${HEX2:12:4}|${HEX3:12:4})$ ]]; then
				LOG 额外检测获得一致端口，请确认是否使用了策略分流
				eval STUN_FLAG_${L4PROTO^^}=1
			else
				LOG 多次端口不同，当前 ${L4PROTO^^} 为对称映射
				eval STUN_FLAG_${L4PROTO^^}=2
			fi
		fi
		LOG $BITCOMET_BT_PORT/$L4PROTO 的检测结果如下
		LOG $(printf '%d.%d.%d.%d\n' $(printf '%x\n' $((0x${HEX1:16:8}^0x2112a442)) | sed 's/../0x& /g')):$((0x${HEX1:12:4}^0x2112)) via $SERVER1
		LOG $(printf '%d.%d.%d.%d\n' $(printf '%x\n' $((0x${HEX2:16:8}^0x2112a442)) | sed 's/../0x& /g')):$((0x${HEX2:12:4}^0x2112)) via $SERVER2
		[ $HEX3 ] && \
		LOG $(printf '%d.%d.%d.%d\n' $(printf '%x\n' $((0x${HEX3:16:8}^0x2112a442)) | sed 's/../0x& /g')):$((0x${HEX3:12:4}^0x2112)) via $SERVER3
		[ $HEX4 ] && \
		LOG $(printf '%d.%d.%d.%d\n' $(printf '%x\n' $((0x${HEX4:16:8}^0x2112a442)) | sed 's/../0x& /g')):$((0x${HEX4:12:4}^0x2112)) via $SERVER4
	else
		LOG 检测 ${L4PROTO^^} 映射行为失败，本次跳过
	fi
}
[ "$STUN" = 0 ] || {
	[ "$StunInterface" ] && {
		(ls /sys/class/net; echo "$HOSTIP") | grep -q ^$StunInterface$ || {
			LOG STUN 绑定接口不存在，已忽略
			unset StunInterface
		}
	}
	[ $StunInterface ] && \
	if [[ $StunInterface =~ ([0-9]{1,3}\.){3}[0-9]{1,3} ]]; then
		export STUN_IFACE=',bind='$StunInterface''
		export STUN_IFACE_IP=1
	else
		export STUN_IFACE=',interface='$StunInterface''
		export STUN_IFACE_IF=1
	fi
	START_NAT tcp
	unset HEX1 HEX2 HEX3 HEX4 SERVER1 SERVER2 SERVER3 SERVER4
	START_NAT udp
	[ "$STUN_FLAG_TCP" = 0 ] && [ "$STUN_FLAG_UDP" = 0 ] && {
		LOG 当前网络为公网映射；自动禁用 STUN，请自行开放端口
		export STUN=0
	}
	[ "$STUN_FLAG_TCP" = 2 ] && [ "$STUN_FLAG_UDP" = 2 ] && {
		LOG 当前网络为对称映射；自动禁用 STUN，请优化 NAT 类型后再尝试
		export STUN=0
	}
}

# 初始化 STUN
[ "$STUN" = 0 ] || {
	[ "$StunMode" ] || LOG 未指定 STUN 穿透模式，自动设置
	[ "$StunMode" ] && [[ ! $StunMode =~ ^(tcp|udp|nfttcp|nftudp|nftboth)$ ]] && {
		LOG 错误的 STUN 穿透模式，重新设置
		unset StunMode
	}
	[[ $StunMode =~ tcp|both ]] && [ "$STUN_FLAG_TCP" != 1 ] && {
		LOG 当前 TCP 非锥形映射，重新设置
		unset StunMode
	}
	[[ $StunMode =~ udp|both ]] && [ "$STUN_FLAG_UDP" != 1 ] && {
		LOG 当前 UDP 非锥形映射，重新设置
		unset StunMode
	}
	[[ $StunMode =~ nft ]] && ! nft list tables >/dev/null 2>&1 && {
		LOG 已指定 nftables 改包模式，但未开启 NET_ADMIN 权限；自动设置为传统模式
		[[ $StunMode =~ ^nftudp$ ]] || export StunMode=tcp
		[[ $StunMode =~ ^nftudp$ ]] && export StunMode=udp
	}
	if [ $StunMode ]; then
		[ $StunMode = tcp ] && LOG 当前使用 TCP 传统模式
		[ $StunMode = udp ] && LOG 当前使用 UDP 传统模式
		[ $StunMode = nfttcp ] && LOG 当前使用 TCP 改包模式
		[ $StunMode = nftudp ] && LOG 当前使用 UDP 改包模式
		[ $StunMode = nftboth ] && LOG 当前使用 TCP + UDP 改包模式
	else
		if nft list tables >/dev/null 2>&1; then
			LOG 已开启 NET_ADMIN 权限，使用 TCP 改包模式
			export StunMode=nfttcp
		else
			LOG 未开启 NET_ADMIN 权限，使用 TCP 传统模式
			export StunMode=tcp
		fi
	fi
	[ $StunModeLite ] && [[ $StunMode =~ nft ]] && {
		[ $StunInterface ] && LOG 指定网络接口时，HTTPS 改包不生效；自动更改为轻量模式 && export StunModeLite=1
		[ $StunInterface ] || LOG 已指定轻量改包模式，忽略 HTTPS Tracker
	}
	[[ ! $StunMode =~ nft ]] && [ $StunModeLite ] && LOG StunModeLite 不适用于传统模式，已忽略 && unset StunModeLite
	[[ ! $StunMode =~ nft ]] && [ $StunHost = 0 ] && LOG 如在 bridge 网络下使用传统模式，请自行解决 UPnP 的可达性
	[[ ! $StunMode =~ nft ]] && [ "$StunUpnp" = 0 ] && LOG 传统模式依赖 UPnP，已强制启用 && unset StunUpnp
}

# 初始化 SSLproxy
[ "$STUN" != 0 ] && [[ $StunMode =~ nft ]] && [ ! $StunModeLite ] && {
	if [ $StunMitmEnPort ]; then
		if [[ $StunMitmEnPort =~ ^[0-9]+$ ]] && [ $StunMitmEnPort -le 65535 ]; then
			[ $StunMitmEnPort -ge 1024 ] || LOG SSLproxy 端口指定为 1024 以下，可能无法监听
			STUN_MITM_ENPORT_ORIG=$StunMitmEnPort
		else
			LOG SSLproxy 端口指定错误，仅接受 65535 以下数字，重新分配
			export StunMitmEnPort=58443
		fi
	else
		export StunMitmEnPort=58443
	fi
	while (>/dev/tcp/0.0.0.0/$StunMitmEnPort) 2>/dev/null || echo $StunMitmEnPort | grep -qE '^('$BITCOMET_WEBUI_PORT'|'$BITCOMET_BT_PORT'|'$PBH_WEBUI_PORT'|'$StunMitmDePort')$' ; do
		export StunMitmEnPort=$(shuf -i 1024-65535 -n 1)
		STUN_MITM_ENPORT_SHUF=1
	done
	[ $STUN_MITM_ENPORT_ORIG ] && [ $STUN_MITM_ENPORT_SHUF ] && LOG SSLproxy 端口 $STUN_MITM_ENPORT_ORIG 被占用，已重新分配 && LOG 注意，当前不支持在 host 网络下执行多个下载器的 HTTPS 解密
	if [ $StunMitmDePort ]; then
		if [[ $StunMitmDePort =~ ^[0-9]+$ ]] && [ $StunMitmDePort -le 65535 ]; then
			[ $StunMitmDePort -ge 1024 ] || LOG SSLproxy 端口指定为 1024 以下，可能无法监听
			STUN_MITM_DEPORT_ORIG=$StunMitmDePort
		else
			LOG SSLproxy 端口指定错误，仅接受 65535 以下数字，重新分配
			export StunMitmDePort=50080
		fi
	else
		export StunMitmDePort=50080
	fi
	while (>/dev/tcp/0.0.0.0/$StunMitmDePort) 2>/dev/null || echo $StunMitmDePort | grep -qE '^('$BITCOMET_WEBUI_PORT'|'$BITCOMET_BT_PORT'|'$PBH_WEBUI_PORT'|'$StunMitmEnPort')$' ; do
		export StunMitmDePort=$(shuf -i 1024-65535 -n 1)
		STUN_MITM_DEPORT_SHUF=1
	done
	[ $STUN_MITM_DEPORT_ORIG ] && [ $STUN_MITM_DEPORT_SHUF ] && LOG socat 端口 $STUN_MITM_DEPORT_ORIG 被占用，已重新分配 && LOG 注意，当前不支持在 host 网络下执行多个下载器的 HTTPS 解密
	STUN_ID=DockerStunCA_$StunMitmEnPort
	mkdir -p /usr/local/share/ca-certificates/
	openssl genrsa -out $STUN_ID.key 2048
	openssl req -new -x509 -days 3650 -key $STUN_ID.key -out $STUN_ID.crt -subj "/C=CN/ST=Shanghai/L=Shanghai/O=BitCometPostBar/OU=STUN/CN=STUN_CA"
	cp -f $STUN_ID.crt /usr/local/share/ca-certificates/
	update-ca-certificates >/dev/null 2>&1
	[ "$PBH" != 0 ] && {
		keytool -delete -alias MITM -cacerts -storepass STUN_CA >/dev/null 2>&1
		keytool -importcert -trustcacerts -file $STUN_ID.crt -cacerts -alias MITM -storepass STUN_CA -noprompt >/dev/null 2>&1
	}
	sslproxy -d -u sslproxy -k $STUN_ID.key -c $STUN_ID.crt -P ssl 0.0.0.0 $StunMitmEnPort up:$StunMitmDePort
	socat TCP-LISTEN:$StunMitmDePort,reuseport,fork EXEC:socat.sh &
}

# 执行 STUN 及 BitComet
START_BITCOMET() {
	[[ $StunMode =~ nft ]] || /files/BitComet/bin/bitcometd | grep -v 'IPFilter loaded' &
	[[ $StunMode =~ nft ]] && runuser -u bitcomet -- /files/BitComet/bin/bitcometd | grep -v 'IPFilter loaded' &
}
if [ "$STUN" = 0 ]; then
	LOG 已禁用 STUN，直接启动 BitComet
	/files/BitComet/bin/bitcometd &
else
	LOG 已启用 STUN，BitComet BT 端口 $BITCOMET_BT_PORT 将作为穿透通道的本地端口
	export STUN_ORIG_PORT=$BITCOMET_BT_PORT
	[[ $StunMode =~ nft ]] || while
		awk '{print$2,$4}' /proc/net/tcp /proc/net/tcp6 | grep 0A | grep -qiE '(0{8}|0{32}):'$(printf '%04x' $BITCOMET_BT_PORT)'' || \
		awk '{print$2,$4}' /proc/net/udp /proc/net/udp6 | grep 07 | grep -qiE '(0{8}|0{32}):'$(printf '%04x' $BITCOMET_BT_PORT)'' || \
		echo $BITCOMET_BT_PORT | grep -qE '^('$BITCOMET_WEBUI_PORT'|'$PBH_WEBUI_PORT'|'$StunMitmEnPort'|'$StunMitmDePort'|'$STUN_ORIG_PORT')$'
	do export BITCOMET_BT_PORT=$(shuf -i 10000-65535 -n 1); done
	[[ $StunMode =~ nft ]] && [ "$StunUpnp" != 0 ] && {
		LOG 已启用 UPnP，添加规则后再启动 BitComet
		[[ $StunMode =~ tcp|both ]] && stun_upnp.sh $STUN_ORIG_PORT $STUN_ORIG_PORT tcp
		[[ $StunMode =~ udp|both ]] && stun_upnp.sh $STUN_ORIG_PORT $STUN_ORIG_PORT udp
	}
	START_BITCOMET
	awk '{print$2,$4}' /proc/net/tcp /proc/net/tcp6 | grep 0A | grep -qiE '(0{8}|0{32}):'$(printf '%04x' $BITCOMET_BT_PORT)'' || {
		LOG BitComet BT 端口未监听，3 秒后重试
		sleep 3
	}
	until awk '{print$2,$4}' /proc/net/tcp /proc/net/tcp6 | grep 0A | grep -qiE '(0{8}|0{32}):'$(printf '%04x' $BITCOMET_BT_PORT)''; do
		let START_TRY++
		[ $START_TRY -ge 15 ] && LOG BitComet BT 端口监听失败，退出容器 && exit 1
		LOG 第 $START_TRY 次重启 BitComet，最多 15 次
		pkill -f bitcometd && sleep 1
		START_BITCOMET && sleep 2
	done
	LOG BitComet 已启动，使用以下地址访问 WebUI
	for IP in $HOSTIP; do LOG http://$IP:$BITCOMET_WEBUI_PORT; done
	[[ $StunMode =~ tcp|both ]] && {
		LOG 已启用 TCP 通道，执行 HTTP 保活
		LOG 若保活失败，穿透通道可能需要在缩短心跳间隔后才稳定
		stun_keep.sh &
	}
	if [ $StunMode = nftboth ]; then
		stun.sh tcp &
		stun.sh udp &
	else
		[[ $StunMode =~ tcp ]] && stun.sh tcp &
		[[ $StunMode =~ udp ]] && stun.sh udp &
	fi
	[[ $StunMode =~ nft ]] && [ $StunHost = 1 ] && (pgrep -f nftables_exit.sh >/dev/null || nftables_exit.sh 2>/dev/null &)
	disown -h $(jobs -p)
fi

# 执行 PeerBanHelper
if [ "$PBH" = 0 ]; then
	LOG 已禁用 PeerBanHelper
else
	LOG 已启用 PeerBanHelper，60 秒后启动
	( sleep 60
	cd /PeerBanHelper
	java $JvmArgs -Dpbh.release=docker -Djava.awt.headless=true -Xmx512M -Xms16M -Xss512k -XX:+UseG1GC -XX:+UseStringDeduplication -XX:+ShrinkHeapInSteps -jar /files/PeerBanHelper/PeerBanHelper.jar >/dev/null 2>&1 &
	LOG PeerBanHelper 已启动，使用以下地址访问 WebUI
	for IP in $HOSTIP; do LOG http://$IP:$PBH_WEBUI_PORT; done
	LOG PeerBanHelper 日志已屏蔽，请从 WebUI 中查看 ) &
fi

# 后期处理
EXIT() {
	LOG 清理容器环境
	pkill -f socat
	pkill -f stun.sh
	pkill -f stun_keep.sh
	pkill -f stun_exec.sh
	pkill -f stun_upnp.sh
	pkill -f stun_upnp_keep.sh
	pkill -f nftables.sh
	sleep 1
	pkill -f nftables_exit.sh
	sleep 2
	pkill -f -9 socat
	sleep 3
	pkill -f bitcometd
}
trap EXIT SIGTERM
wait
