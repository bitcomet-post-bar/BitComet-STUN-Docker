#!/bin/bash

# 防止脚本重复运行
pkill -9 -Af "$0 $*"

NFTNAME=$1
CLEANUP() {
	for HANDLE in $(nft -as list chain ip STUN BTTR_HTTP | grep \"$NFTNAME\" | awk '{print$NF}'); do nft delete rule ip STUN BTTR_HTTP handle $HANDLE; done
	for HANDLE in $(nft -as list chain ip STUN BTTR_UDP | grep \"$NFTNAME\" | awk '{print$NF}'); do nft delete rule ip STUN BTTR_UDP handle $HANDLE; done
	nft list chain ip STUN BTTR_HTTP | grep -qvE '[{}]$' || nft delete chain ip STUN BTTR_HTTP
	nft list chain ip STUN BTTR_UDP | grep -qvE '[{}]$' ] || nft delete chain ip STUN BTTR_UDP
	nft -as list chain ip STUN DNAT 2>/dev/null | grep \"$NFTNAME\" && {
		for HANDLE in $(nft -as list chain ip STUN DNAT | grep \"$NFTNAME\" | awk '{print$NF}'); do nft delete rule ip STUN BTTR_HTTP handle $HANDLE; done
		nft list chain ip STUN DNAT | grep -qvE '[{}]$' ] || nft delete chain ip STUN DNAT
	}
	[ $StunModeLite ] || {
		for HANDLE in $(nft -as list chain ip STUN MITM_OUTPUT | grep \"$NFTNAME\" | awk '{print$NF}'); do nft delete rule ip STUN MITM_OUTPUT handle $HANDLE; done
		nft list chain ip STUN MITM_OUTPUT | grep -qvE '[{}]$' || nft delete chain ip STUN MITM_OUTPUT
	}
	nft list chain ip STUN BTTR_NOFT 2>/dev/null | grep -q \"$NFTNAME\" && {
		for HANDLE in $(nft -as list chain ip STUN BTTR_NOFT | grep \"$NFTNAME\" | awk '{print$NF}'); do nft delete rule ip STUN BTTR_NOFT handle $HANDLE; done
		nft list chain ip STUN BTTR_NOFT | grep -qvE '[{}]$' || nft delete chain ip STUN BTTR_NOFT
		TABLE=$(nft -st list ruleset | sed '/flow add @/q' | grep -oE '^table.*\{' | awk '{print$2,$3}' | tail -1)
		CHAIN=$(nft -st list ruleset | sed '/flow add @/q' | grep -oE 'chain.*\{' | awk '{print$2}' | tail -1)
		[ $TABLE ] && [ $CHAIN ] && for HANDLE in $(nft -as list chain ip $TABLE $CHAIN | grep \"${NFTNAME}_noft\" | awk '{print$NF}'); do nft delete rule $TABLE $CHAIN handle $HANDLE; done
	}
	nft list table ip STUN | grep -q 'chain BTTR_' || nft delete table ip STUN
	echo 清理 nftables 规则完成 | tee -a /BitComet/DockerLogs.log
}
trap CLEANUP SIGTERM
sleep infinity &
wait
