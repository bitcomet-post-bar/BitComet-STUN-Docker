#!/bin/bash

WANADDR=$1
WANPORT=$2
LANPORT=$4
L4PROTO=$5
OWNADDR=$6

APPPORT=$LANPORT
OWNNAME=Docker_BitComet_$LANPORT
[ "$StunInterface" ] && \
if [[ "$StunInterface" =~ ([0-9]{1,3}\.){3}[0-9]{1,3} ]]; then
	LOG nftables 不支持 IP 形式 $(echo $StunInterface | awk '{print$2}') 绑定接口，已忽略
else
	IFNAME=$(echo $StunInterface | awk '{print$NF}')
fi

# 定义日志函数
LOG() { echo "$*" | tee -a /BitComet/DockerLogs.log ;}

# 防止脚本重复运行
kill $(ps x | grep $0 | grep $L4PROTO | grep -v grep | awk '{print$1}' | grep -v $$) 2>/dev/null

# 若规则未发生变化，则退出脚本
[ -f StunNftables ] && nft -st list table ip STUN 2>&1 | grep $OWNNAME | grep -q $(printf '0x%x' $WANPORT) && \
LOG nftables 规则已存在，无需更新 && exit

# 防止脚本同时操作 nftables 导致冲突
[ $L4PROTO = udp ] && while ps x | grep $0 | grep -q tcp; do sleep 1; done

# 初始化 nftables
nft add table ip STUN
nft add chain ip STUN BTTR { type filter hook postrouting priority filter \; }
nft flush chain ip STUN BTTR
WANTCP=$(awk '{print$1}' StunPort_tcp 2>/dev/null)
WANUDP=$(awk '{print$1}' StunPort_udp 2>/dev/null)
[ $IFNAME ] && OIFNAME='oifname '$IFNAME''
# BitComet 目前指定 UID 会导致无法热更新端口
# APPRULE='skuid 56082'
APPRULE='fib saddr type local'
if nft -c add rule ip STUN BTTR @ih,0,16 0 2>/dev/null; then
	OFFSET_BASE='@ih'
	OFFSET_HTTP_GET='@ih,0,112'
	OFFSET_HTTP_SEQ='seq 768 16 1088'
	OFFSET_UDP_MAGIC='@ih,0,64'
	OFFSET_UDP_ACTION='@ih,64,32'
	OFFSET_UDP_PORT='@ih,768,16'
else
	OFFSET_BASE='@th'
	OFFSET_HTTP_GET='@th,160,112'
	OFFSET_HTTP_SEQ='seq 928 16 1248'
	OFFSET_UDP_MAGIC='@th,64,64'
	OFFSET_UDP_ACTION='@th,128,32'
	OFFSET_UDP_PORT='@th,832,16'
fi

# HTTP Tracker
STRAPP=0x706f72743d$(printf $APPPORT | xxd -p)
STRTCP=0x3d$(printf 30$(printf "$WANTCP" | xxd -p) | tail -c 10)
STRUDP=0x3d$(printf 30$(printf "$WANUDP" | xxd -p) | tail -c 10)
if [ $WANTCP ] && [ $WANUDP ]; then
	SETSTR='jhash ip daddr mod 2 map { 0 : '$STRTCP', 1 : '$STRUDP' }'
elif [ $WANTCP ]; then
	SETSTR=$STRTCP
elif [ $WANUDP ]; then
	SETSTR=$STRUDP
fi
nft add set ip STUN BTTR_HTTP "{ type ipv4_addr . inet_service; flags dynamic; timeout 1h; }"
nft add chain ip STUN BTTR_HTTP
nft insert rule ip STUN BTTR ip daddr . tcp dport @BTTR_HTTP goto BTTR_HTTP
nft add rule ip STUN BTTR $OFFSET_HTTP_GET 0x474554202f616e6e6f756e63653f add @BTTR_HTTP { ip daddr . tcp dport } goto BTTR_HTTP
for HANDLE in $(nft -as list chain ip STUN BTTR_HTTP | grep \"$OWNNAME\" | awk '{print$NF}'); do nft delete rule ip STUN BTTR_HTTP handle $HANDLE; done
for OFFSET in $($OFFSET_HTTP_SEQ); do
	nft insert rule ip STUN BTTR_HTTP $OIFNAME $APPRULE $OFFSET_BASE,$OFFSET,80 $STRAPP $OFFSET_BASE,$(($OFFSET+32)),48 set $SETSTR counter accept comment $OWNNAME
done
nft insert rule ip STUN BTTR_HTTP ip daddr != 127.0.0.1 update @BTTR_HTTP { ip daddr . tcp dport } comment $OWNNAME

# UDP Tracker
if [ $WANTCP ] && [ $WANUDP ]; then
	SETNUM='jhash ip daddr mod 2 map { 0 : '$WANTCP', 1 : '$WANUDP' }'
elif [ $WANTCP ]; then
	SETNUM=$WANTCP
elif [ $WANUDP ]; then
	SETNUM=$WANUDP
fi
nft add set ip STUN BTTR_UDP "{ type ipv4_addr . inet_service; flags dynamic; timeout 1h; }"
nft add chain ip STUN BTTR_UDP
nft insert rule ip STUN BTTR ip daddr . udp dport @BTTR_UDP goto BTTR_UDP
nft add rule ip STUN BTTR $OFFSET_UDP_MAGIC 0x41727101980 $OFFSET_UDP_ACTION 0 add @BTTR_UDP { ip daddr . udp dport } goto BTTR_UDP
for HANDLE in $(nft -as list chain ip STUN BTTR_UDP | grep \"$OWNNAME\" | awk '{print$NF}'); do nft delete rule ip STUN BTTR_UDP handle $HANDLE; done
nft insert rule ip STUN BTTR_UDP $OIFNAME $APPRULE $OFFSET_UDP_ACTION 1 $OFFSET_UDP_PORT $APPPORT $OFFSET_UDP_PORT set $SETNUM update @BTTR_UDP { ip daddr . udp dport } counter accept comment $OWNNAME

# HTTPS Trackers
[ $StunModeLite ] || {
	LOG 获取 HTTPS Tracker 列表，最多等待 15 秒
	echo -ne "GET /https_trackers.txt HTTP/1.1\r\nHost: oniicyan.pages.dev\r\nConnection: close\r\n\r\n" | \
	timeout 15 openssl s_client -connect oniicyan.pages.dev:443 -quiet 2>/dev/null | grep -oE 'https://.*' >/tmp/HttpsTrackers.txt
	if [ -s /tmp/HttpsTrackers.txt ]; then
		LOG 获取 HTTPS Tracker 列表成功
		if cmp -s /tmp/HttpsTrackers.txt HttpsTrackers.txt; then
			rm -f /tmp/HttpsTrackers.txt
		else
			mv -f /tmp/HttpsTrackers.txt HttpsTrackers.txt
		fi
	else
		LOG 获取 HTTPS Tracker 列表失败，本次跳过
		[ -f HttpsTrackers.txt ] || cp /files/HttpsTrackers.txt HttpsTrackers.txt
	fi
	LOG 解析 HTTPS Tracker 列表，可能需要一些时间
	nft add set ip STUN BTTR_HTTPS "{ type ipv4_addr . inet_service; }"
	nft flush set ip STUN BTTR_HTTPS
	for SERVER in $(awk -F / '{print $3}' HttpsTrackers.txt); do
		DOMAIN=$(echo $SERVER | awk -F : '{print$1}')
		PORT=$(echo $SERVER | awk -F : '{print$2}')
		for IP in $(getent ahosts $DOMAIN | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort | uniq); do
			[[ $IP =~ 0\.0\.0\.0|127\.0\.0\.1 ]] && continue
			nft add element ip STUN BTTR_HTTPS { $IP . $PORT }
		done
	done
	[ -f /BitComet/CustomHttpsTrackers.txt ] || cp /files/CustomHttpsTrackers.txt /BitComet/CustomHttpsTrackers.txt
	for LINE in $(grep -v '#.*' /BitComet/CustomHttpsTrackers.txt); do
		if echo $LINE | grep -q https://; then
			SERVER=$(echo $LINE | awk -F / '{print $3}')
			DOMAIN=$(echo $SERVER | awk -F : '{print$1}')
			PORT=$(echo $SERVER | awk -F : '{print$2}')
			[ $PORT ] || PORT=443
			for IP in $(getent ahosts $DOMAIN | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort | uniq); do
				[[ $IP =~ 0\.0\.0\.0|127\.0\.0\.1 ]] && continue
				nft add element ip STUN BTTR_HTTPS { $IP . $PORT }
			done
		else
			LIST="$LIST"$'\n'$LINE
		fi
	done
	[ "$LIST" ] && {
		LOG 以下自定义 HTTPS Tracker 格式不正确，已忽略
		LOG "$(echo "$LIST" | sed '/^$/d')"
	}
	nft add chain ip STUN MITM_OUTPUT { type nat hook output priority dstnat \; }
	for HANDLE in $(nft -as list chain ip STUN MITM_OUTPUT | grep \"$OWNNAME\" | awk '{print$NF}'); do nft delete rule ip STUN MITM_OUTPUT handle $HANDLE; done
	nft insert rule ip STUN MITM_OUTPUT $OIFNAME $APPRULE skuid != 58443 ip daddr . tcp dport @BTTR_HTTPS counter redirect to $StunMitmEnPort comment $OWNNAME
	nft insert rule ip STUN BTTR ip daddr 127.0.0.1 $OFFSET_HTTP_GET 0x474554202f616e6e6f756e63653f goto BTTR_HTTP
}

# 绕过软件加速
nft -st list ruleset 2>/dev/null | grep -q @ft && {
	CTMARK=0x$(echo $OWNNAME | md5sum | cut -c -8)
	nft add chain ip STUN BTTR_NOFT { type filter hook forward priority filter - 5 \; }
	for HANDLE in $(nft -as list chain ip STUN BTTR_NOFT | grep \"$OWNNAME\" | awk '{print$NF}'); do nft delete rule ip STUN BTTR_NOFT handle $HANDLE; done
	nft add rule ip STUN BTTR_NOFT $OIFNAME ct mark $CTMARK accept
	nft add rule ip STUN BTTR_NOFT $OIFNAME $APPRULE ip daddr . tcp dport @BTTR_HTTP counter ct mark set $CTMARK comment $OWNNAME
	nft add rule ip STUN BTTR_NOFT $OIFNAME $APPRULE ip daddr . udp dport @BTTR_UDP counter ct mark set $CTMARK comment $OWNNAME
	ps x | grep -q $CTMARK || nohup nftables_noft.sh $CTMARK &
}

# 容器退出时清理 nftables 规则
[ $StunHost = 1 ] && (ps x | grep -q $OWNNAME || nohup nftables_cleanup.sh $OWNNAME $CTMARK &)

>StunNftables
LOG 更新 nftables 规则完成
