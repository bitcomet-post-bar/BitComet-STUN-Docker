#!/bin/sh

WANADDR=$1
WANPORT=$2
LANPORT=$4
L4PROTO=$5
OWNADDR=$6

# 定义日志函数
LOG() { tee -a /BitComet/DockerLogs.log ;}

echo 当前穿透通道为 $WANADDR:$WANPORT | LOG

# 保存穿透信息
touch /BitComet/DockerSTUN.log
[ $(wc -l </BitComet/DockerSTUN.log) -ge 1000 ] && mv /BitComet/DockerSTUN.log /BitComet/DockerSTUN.log.old
echo [$(date)] $WANADDR:$WANPORT '->' $OWNADDR:$LANPORT '->' $WANPORT >>/BitComet/DockerSTUN.log
echo $WANPORT $LANPORT >/BitComet/DockerSTUNPORT

[ $UpnpInterface ] && export UpnpInterface='-m '$UpnpInterface''
[ $UpnpUrl ] && export UpnpUrl='-u '$UpnpUrl''
[ $UpnpAddr ] || export UpnpAddr=@
echo 本次 UPnP 规则：转发 外部端口 $LANPORT 至 内部端口 $WANPORT | LOG
UpnpStart='upnpc '$UpnpArgs' '$UpnpInterface' '$UpnpUrl' -i -e "STUN BitComet Docker" -a '$UpnpAddr' '$WANPORT' '$LANPORT' '$L4PROTO''
echo 本次 UPnP 执行命令 | LOG
echo $UpnpStart | LOG
UpnpErr=$(eval $UpnpStart 2>&1 >/dev/null)
[ "$UpnpErr" ] && echo 添加 UPnP 规则失败，错误信息如下 | LOG && echo $UpnpErr | LOG && \
[ $UpnpInterface ] || (
[ $(ls /sys/class/net | grep -o br-lan) ] && (
echo 尝试使用 br-lan 接口添加 UPnP 规则 | LOG
UpnpStart='upnpc '$UpnpArgs' -m br-lan '$UpnpUrl' -i -e "STUN BitComet Docker" -a '$UpnpAddr' '$WANPORT' '$LANPORT' '$L4PROTO''
echo 本次 UPnP 执行命令 | LOG
echo $UpnpStart | LOG
eval $UpnpStart >/dev/null ))

echo 更新 BitComet 监听端口 | LOG
/files/BitComet/bin/bitcometd --bt_port $WANPORT &
