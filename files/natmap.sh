#!/bin/sh

WANADDR=$1
WANPORT=$2
LANPORT=$4
L4PROTO=$5
OWNADDR=$6

# 定义日志函数
LOG() { tee -a /BitComet/DockerLogs.log ;}

echo 当前穿透通道为 $WANADDR:$WANPORT，即将更新 BitComet 监听端口 | LOG
/files/BitComet/bin/bitcometd --bt_port $WANPORT

echo 开始执行 UPnP | LOG
[ $UpnpInterface ] && UpnpInterface='-m '$UpnpInterface''
UPNPC=$(upnpc $UpnpInterface -i -e "STUN BitComet Docker" -a @ $WANPORT $LANPORT $L4PROTO 2>&1 >/dev/null)
[ $UPNPC ] && echo $UPNPC | LOG
