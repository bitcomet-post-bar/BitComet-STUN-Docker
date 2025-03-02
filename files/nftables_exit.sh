#!/bin/bash

# 防止脚本重复运行
pkill -9 -Af $0

NFTNAME=Docker_BitComet_$STUN_ORIG_PORT
CLEANUP() {
	for HANDLE in $(nft -as list chain ip STUN BTTR_HTTP | grep \"$NFTNAME\" | awk '{print$NF}'); do nft delete rule ip STUN BTTR_HTTP handle $HANDLE; done
	for HANDLE in $(nft -as list chain ip STUN BTTR_UDP | grep \"$NFTNAME\" | awk '{print$NF}'); do nft delete rule ip STUN BTTR_UDP handle $HANDLE; done
	for HANDLE in $(nft -as list chain ip STUN NAT_OUTPUT | grep \"${NFTNAME}_snat\" | awk '{print$NF}'); do nft delete rule ip STUN NAT_OUTPUT handle $HANDLE; done
	for HANDLE in $(nft -as list chain ip STUN NAT_OUTPUT | grep \"${NFTNAME}_mitm\" | awk '{print$NF}'); do nft delete rule ip STUN NAT_OUTPUT handle $HANDLE; done
	for HANDLE in $(nft -as list chain ip STUN NAT_POSTROUTING | grep \"$NFTNAME\" | awk '{print$NF}'); do nft delete rule ip STUN NAT_POSTROUTING handle $HANDLE; done
	[ $StunModeLite ] || nft list chain ip STUN NAT_OUTPUT | grep -q BTTR_HTTPS || nft delete set ip STUN BTTR_HTTPS
	nft list chain ip STUN BTTR_HTTP | grep -qvE '[{}]$|policy accept' || nft delete chain ip STUN BTTR_HTTP
	nft list chain ip STUN BTTR_UDP | grep -qvE '[{}]$|policy accept' ] || nft delete chain ip STUN BTTR_UDP
	nft list chain ip STUN NAT_OUTPUT | grep -qvE '[{}]$|policy accept' || nft delete chain ip STUN NAT_OUTPUT
	nft list chain ip STUN NAT_POSTROUTING | grep -qvE '[{}]$|policy accept' ] || nft delete chain ip STUN NAT_POSTROUTING
	nft list table ip STUN | grep -q 'chain BTTR_' || nft delete table ip STUN
	echo 清理 nftables 规则完成 | tee -a /BitComet/DockerLogs.log
}
trap CLEANUP SIGTERM
sleep infinity &
wait
