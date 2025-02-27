#!/bin/bash

# 防止脚本重复运行
pkill -9 -Af "$0 $*"

NFTNAME=Docker_BitComet_$STUN_ORIG_PORT
CLEANUP() {
	echo 清理 nftables 规则 | tee -a /BitComet/DockerLogs.log
	for HANDLE in $(nft -as list chain ip STUN MARK | grep \"$NFTNAME\" | awk '{print$NF}'); do nft delete rule ip STUN MARK handle $HANDLE; done
	for HANDLE in $(nft -as list chain ip STUN SNAT | grep \"$NFTNAME\" | awk '{print$NF}'); do nft delete rule ip STUN SNAT handle $HANDLE; done
	for HANDLE in $(nft -as list chain ip STUN BTTR_HTTP | grep \"$NFTNAME\" | awk '{print$NF}'); do nft delete rule ip STUN BTTR_HTTP handle $HANDLE; done
	for HANDLE in $(nft -as list chain ip STUN BTTR_UDP | grep \"$NFTNAME\" | awk '{print$NF}'); do nft delete rule ip STUN BTTR_UDP handle $HANDLE; done
	nft list chain ip STUN MARK | grep -qvE '[{}]$|policy accept' || nft delete chain ip STUN MARK
	nft list chain ip STUN SNAT | grep -qvE '[{}]$|policy accept' ] || nft delete chain ip STUN SNAT
	nft list chain ip STUN BTTR_HTTP | grep -qvE '[{}]$|policy accept' || nft delete chain ip STUN BTTR_HTTP
	nft list chain ip STUN BTTR_UDP | grep -qvE '[{}]$|policy accept' ] || nft delete chain ip STUN BTTR_UDP
	[ $StunModeLite ] || {
		for HANDLE in $(nft -as list chain ip STUN MITM_OUTPUT | grep \"$NFTNAME\" | awk '{print$NF}'); do nft delete rule ip STUN MITM_OUTPUT handle $HANDLE; done
		nft list chain ip STUN MITM_OUTPUT | grep -qvE '[{}]$|policy accept' || {
			nft delete chain ip STUN MITM_OUTPUT
			nft delete set ip STUN BTTR_HTTPS
		}
	}
	nft list chain ip STUN BTTR_NOFT 2>/dev/null | grep -q \"$NFTNAME\" && {
		for HANDLE in $(nft -as list chain ip STUN BTTR_NOFT | grep \"$NFTNAME\" | awk '{print$NF}'); do nft delete rule ip STUN BTTR_NOFT handle $HANDLE; done
		nft list chain ip STUN BTTR_NOFT | grep -qvE '[{}]$' || nft delete chain ip STUN BTTR_NOFT
		TABLE=$(nft -st list ruleset | sed '/flow add @/q' | grep -oE '^table.*\{' | awk '{print$2,$3}' | tail -1)
		CHAIN=$(nft -st list ruleset | sed '/flow add @/q' | grep -oE 'chain.*\{' | awk '{print$2}' | tail -1)
		[ "$TABLE" ] && [ "$CHAIN" ] && for HANDLE in $(nft -as list chain $TABLE $CHAIN | grep \"${NFTNAME}_noft\" | awk '{print$NF}'); do nft delete rule $TABLE $CHAIN handle $HANDLE; done
	}
	nft list table ip STUN | grep -q 'chain BTTR_' || nft delete table ip STUN
	echo 清理 nftables 规则完成 | tee -a /BitComet/DockerLogs.log
}
trap CLEANUP SIGTERM
sleep infinity &
wait
