#!/bin/bash

# 防止脚本重复运行
kill -9 $(ps x | grep $0 | grep -v grep | awk '{print$1}' | grep -v $$) 2>/dev/null

OWNNAME=$1
CTMARK=$2
CLEANUP () {
	for HANDLE in $(nft -as list chain ip STUN BTTR_HTTP | grep \"$OWNNAME\" | awk '{print$NF}'); do nft delete rule ip STUN BTTR_HTTP handle $HANDLE; done
	for HANDLE in $(nft -as list chain ip STUN BTTR_UDP | grep \"$OWNNAME\" | awk '{print$NF}'); do nft delete rule ip STUN BTTR_UDP handle $HANDLE; done
	nft list chain ip STUN BTTR_HTTP | grep -qvE '[{}]$' || nft delete chain ip STUN BTTR_HTTP
	nft list chain ip STUN BTTR_UDP | grep -qvE '[{}]$' ] || nft delete chain ip STUN BTTR_UDP
	[ $StunModeLite ] || {
		for HANDLE in $(nft -as list chain ip STUN BTTR_HTTPS | grep \"$OWNNAME\" | awk '{print$NF}'); do nft delete rule ip STUN BTTR_HTTPS handle $HANDLE; done
		nft list chain ip STUN BTTR_HTTPS | grep -qvE '[{}]$' || nft delete chain ip STUN BTTR_HTTPS
	}
	[ $CTMARK ] && {
		for HANDLE in $(nft -as list chain ip STUN BTTR_NOFT | grep \"$OWNNAME\" | awk '{print$NF}'); do nft delete rule ip STUN BTTR_NOFT handle $HANDLE; done
		nft list chain ip STUN BTTR_NOFT | grep -qvE '[{}]$' || nft delete chain ip STUN BTTR_NOFT
		TABLE=$(nft -st list ruleset | sed '/flow add @/q' | grep -oE '^table.*\{' | awk '{print$2,$3}' | tail -1)
		CHAIN=$(nft -st list ruleset | sed '/flow add @/q' | grep -oE 'chain.*\{' | awk '{print$2}' | tail -1)
		[ $TABLE ] && [ $CHAIN ] && for HANDLE in $(nft -as list chain ip $TABLE $CHAIN | grep \"${OWNNAME}_noft\" | awk '{print$NF}'); do nft delete rule $TABLE $CHAIN handle $HANDLE; done
	}
	nft list table ip STUN | grep -q 'chain BTTR_' || nft delete table ip STUN
	echo 清理 nftables 规则完成 | tee -a /BitComet/DockerLogs.log
}
trap CLEANUP TERM INT
sleep infinity
