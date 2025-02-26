#!/bin/bash

# 防止脚本重复运行
pkill -Af "$0 $*"

CTMARK=$1
TABLE=$(nft -st list ruleset | sed '/flow add @/q' | grep -oE '^table.*\{' | awk '{print$2,$3}' | tail -1)
CHAIN=$(nft -st list ruleset | sed '/flow add @/q' | grep -oE 'chain.*\{' | awk '{print$2}' | tail -1)
NFTNAME=Docker_BitComet_$STUN_ORIG_PORT
while :; do
	nft -s list chain $TABLE $CHAIN | grep -q ${NFTNAME}_noft || {
		HANDLE=$(nft -as list chain $TABLE $CHAIN | sed '/flow add @/q' | awk 'END{print$NF}')
		[ $HANDLE ] && {
			echo 检测到软件加速，绕过 Tracker 流量 | tee -a /BitComet/DockerLogs.log
			nft insert rule $TABLE $CHAIN handle $HANDLE $OIFNAME $APPRULE tcp flags { syn, ack } accept comment ${NFTNAME}_noft
			nft insert rule $TABLE $CHAIN handle $HANDLE $OIFNAME $APPRULE ct mark $CTMARK counter accept comment ${NFTNAME}_noft
		}
	}
	sleep 60
done
