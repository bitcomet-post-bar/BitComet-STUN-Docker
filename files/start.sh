#!/bin/sh

# 初始化变量
[ $STUN ] && ([ $Stun ] || export Stun=$STUN)
[ $BITCOMET_WEBUI_USERNAME ] && export WEBUI_USERNAME=$BITCOMET_WEBUI_USERNAME
[ $BITCOMET_WEBUI_PASSWORD ] && export WEBUI_PASSWORD=$BITCOMET_WEBUI_PASSWORD

# 初始化日志函数
LOG() { tee -a /BitComet/DockerLogs.log ;}

echo 开始执行 BitComet 贴吧修改版 | tee /tmp/DockerLogs.log

# 初始化配置目录
for DIR in /BitComet /PeerBanHelper; do
	mount | grep ' '$DIR' ' >/dev/null || {
	echo $DIR 目录未挂载 | tee -a /tmp/DockerLogs.log
	DIR_CFG_FLAG=1
	[ -d $DIR ] || mkdir $DIR ;}
done
mv -f /BitComet/DockerLogs.log /BitComet/DockerLogs.old 2>/dev/null
mv -f /tmp/DockerLogs.log /BitComet/DockerLogs.log
[ $DIR_CFG_FLAG ] && echo 应用程序配置及数据保存到容器层，重启后可能会丢失 | LOG

# 初始化 BitComet 配置文件
BC_CFG=/BitComet/BitComet.xml
[ -f $BC_CFG ] || (
echo BitComet 配置文件不存在，执行初始化 | LOG
cp /files/BitComet/BitComet.xml $BC_CFG )
grep DefaultDownloadPath $BC_CFG | grep /Downloads >/dev/null || sed 's,<Settings>,<Settings><DefaultDownloadPath>/Downloads</DefaultDownloadPath>,' -i $BC_CFG
grep EnableTorrentShare $BC_CFG | grep false >/dev/null || sed 's,<Settings>,<Settings><EnableTorrentShare>false</EnableTorrentShare>,' -i $BC_CFG

# 初始化 BitComet 保存位置
if mount | grep ' /Downloads ' >/dev/null; then
	echo /Downloads 目录已挂载 | LOG
else
	echo /Downloads 目录未挂载，默认保存位置将不可用 | LOG
	BC_DL_FLAG=1
fi
BC_DL_DIR=$(mount | grep -E '^/' | grep -vE ' (/Downloads|/BitComet|/PeerBanHelper|/tmp|/etc/resolv.conf|/etc/hostname|/etc/hosts) ' | awk '{print$3}')
if [ $BC_DL_DIR ]; then
	echo 以下目录将作为 BitComet 的自定义保存位置 | LOG
	for DIR in $BC_DL_DIR; do echo $DIR | LOG; done
	sed 's,<Settings>,<Settings><DirCandidate>'$(echo $BC_DL_DIR | sed 's, /,|/,')'</DirCandidate>,' -i $BC_CFG
else
	[ $BC_DL_FLAG ] && echo 未挂载任何下载目录，任务将无法开始 | LOG
fi

# 初始化 BitComet WebUI 用户名与密码
[ $WEBUI_USERNAME ] || \
export WEBUI_USERNAME=$(grep WebInterfaceUsername $BC_CFG | grep -oE '>.*<' | tr -d '><')
[ $WEBUI_PASSWORD ] || \
export WEBUI_PASSWORD=$(grep WebInterfacePassword $BC_CFG | grep -oE '>.*<' | tr -d '><')
[ $WEBUI_USERNAME = 'test' ] && {
unset WEBUI_USERNAME
echo 禁止使用用户名 test，已清除 ;}
[ $WEBUI_PASSWORD = 'test' ] && {
unset WEBUI_PASSWORD
echo 禁止使用密码 test，已清除 ;}
[ $WEBUI_USERNAME ] || {
export WEBUI_USERNAME=$(base64 /proc/sys/kernel/random/uuid | cut -c -8)
echo BitComet WebUI 用户名未指定，随机生成以下 8 位用户名 | LOG
echo $WEBUI_USERNAME | LOG ;}
[ $WEBUI_PASSWORD ] || {
export WEBUI_PASSWORD=$(base64 /proc/sys/kernel/random/uuid | cut -c -16)
echo BitComet WebUI 密码未指定，随机生成以下 16 位密码 | LOG
echo $WEBUI_PASSWORD | LOG ;}
>/BitComet/Secrect
echo WebInterfaceUsername: $WEBUI_USERNAME >>/BitComet/Secrect
echo WebInterfacePassword: $WEBUI_PASSWORD >>/BitComet/Secrect
echo BitComet WebUI 用户名与密码已保存至 /BitComet/Secrect | LOG

# 初始化 BitComet WebUI 端口
[ $BITCOMET_WEBUI_PORT ] || \
export BITCOMET_WEBUI_PORT=$(grep WebInterfacePort $BC_CFG | grep -oE '>.*<' | tr -d '><')
if [ $BITCOMET_WEBUI_PORT ]; then
	# if [[ $BITCOMET_WEBUI_PORT =~ ^[0-9]+$ ]] && [ $BITCOMET_WEBUI_PORT -le 65535 ]; then
	if [ $(echo $BITCOMET_WEBUI_PORT | grep -E '^[0-9]+$') ] && [ $BITCOMET_WEBUI_PORT -le 65535 ]; then
		[ $BITCOMET_WEBUI_PORT -ge 1024 ] || echo BitComet WebUI 端口指定为 1024 以下，可能无法监听 | LOG
		BC_WEBUI_PORT_ORIG=$BITCOMET_WEBUI_PORT
	else
		echo BitComet WebUI 端口指定错误，仅接受 65535 以下数字，执行初始化 | LOG
		BC_WEBUI_PORT_FLAG=1
	fi
else
	echo BitComet WebUI 端口未指定，执行初始化 | LOG
	BC_WEBUI_PORT_FLAG=1
fi
[ $BC_WEBUI_PORT_FLAG ] && export BITCOMET_WEBUI_PORT=8080
while (>/dev/tcp/127.0.0.1/$BITCOMET_WEBUI_PORT) 2>/dev/null; do
	export BITCOMET_WEBUI_PORT=$(shuf -i 1024-65535 -n 1)
	BC_WEBUI_PORT_SHUF=1
done
if [ $BC_WEBUI_PORT_FLAG ] || [ ! $BC_WEBUI_PORT_SHUF ]; then
	echo BitComet WebUI 当前地址为 http://${HOSTNAME}:$BITCOMET_WEBUI_PORT | LOG
else
	echo BitComet WebUI 端口 $BC_WEBUI_PORT_ORIG 被占用，当前地址为 http://${HOSTNAME}:$BITCOMET_WEBUI_PORT | LOG
fi

# 初始化 PeerBanHelper 配置文件
PBH_CFG=/PeerBanHelper/data/config/config.yml
if [ -f $PBH_CFG ]; then
	[ $(sed -n '/^server:/,/^[^ ]/{/^ \+address:/p}' $PBH_CFG | awk -F : '{print$2}') ] || \
	echo PeerBanHelper 配置文件不正确，执行初始化 | LOG
	cp -f /files/PeerBanHelper/config.yml $PBH_CFG
else
	echo PeerBanHelper 配置文件不存在，执行初始化 | LOG
	mkdir -p /PeerBanHelper/data/config
	cp /files/PeerBanHelper/config.yml $PBH_CFG
fi

# 初始化 PeerBanHelper WebUI Token
[ $PBH_WEBUI_TOKEN ] || \
export PBH_WEBUI_TOKEN=$(sed -n '/^server:/,/^[^ ]/{/^ \+token:/p}' $PBH_CFG | awk -F : '{print$2}')
[ $PBH_WEBUI_TOKEN ] || {
export PBH_WEBUI_TOKEN=$(cat /proc/sys/kernel/random/uuid)
echo PeerBanHelper WebUI Token 未指定，随机生成以下 Token | LOG
echo $PBH_WEBUI_TOKEN | LOG
if [ "$(sed -n '/^server:/,/^[^ ]/{/^ \+token:/p}' $PBH_CFG)" ]; then
	sed '/^server:/,/^[^ ]/{/^ \+token:/{s/token:.*/token: '$PBH_WEBUI_TOKEN'/}}' -i $PBH_CFG
else
	PBH_TOKEN_STR=$(sed -n '/^server:/,/^[^ ]/{/^ \+address:/{s/address:.*/token: '$PBH_WEBUI_TOKEN'/p}}' $PBH_CFG)
	sed '/^server:/a\'"$PBH_TOKEN_STR"'' -i $PBH_CFG
fi ;}
echo $PBH_WEBUI_TOKEN >/PeerBanHelper/Secrect
echo PeerBanHelper WebUI Token 已保存至 /PeerBanHelper/Secrect | LOG

# 初始化 PeerBanHelper WebUI 端口
[ $PBH_WEBUI_PORT ] || \
export PBH_WEBUI_PORT=$(sed -n '/^server:/,/^[^ ]/{/^ \+http:/p}' $PBH_CFG | awk -F : '{print$2}' | tr -d ' "')
if [ $PBH_WEBUI_PORT ]; then
	if [ $(echo $PBH_WEBUI_PORT | grep -E '^[0-9]+$') ] && [ $PBH_WEBUI_PORT -le 65535 ]; then
		[ $PBH_WEBUI_PORT -ge 1024 ] || echo PeerBanHelper WebUI 端口指定为 1024 以下，可能无法监听 | LOG
		PBH_PORT_ORIG=$PBH_WEBUI_PORT
	else
		echo PeerBanHelper WebUI 端口指定错误，仅接受 65535 以下数字，执行初始化 | LOG
		PBH_PORT_FLAG=1
	fi
else
	echo PeerBanHelper WebUI 端口未指定，执行初始化 | LOG
	PBH_PORT_FLAG=1
fi
[ $PBH_PORT_FLAG ] && export PBH_WEBUI_PORT=9898
while (>/dev/tcp/127.0.0.1/$PBH_WEBUI_PORT) 2>/dev/null; do
	export PBH_WEBUI_PORT=$(shuf -i 1024-65535 -n 1)
	PBH_PORT_SHUF=1
done
if [ $PBH_PORT_FLAG ] || [ ! $PBH_PORT_SHUF ]; then
	echo PeerBanHelper WebUI 当前地址为 http://${HOSTNAME}:$PBH_WEBUI_PORT | LOG
else
	echo PeerBanHelper WebUI 端口 $PBH_PORT_ORIG 被占用，当前地址为 http://${HOSTNAME}:$PBH_WEBUI_PORT | LOG
fi
[ $PBH_WEBUI_PORT != "$PBH_PORT_ORIG" ] && \
if [ "$(sed -n '/^server:/,/^[^ ]/{/^ \+http:/p}' $PBH_CFG)" ]; then
	sed '/^server:/,/^[^ ]/{/^ \+http:/{s/http:.*/http: '$PBH_WEBUI_PORT'/}}' -i $PBH_CFG
else
	PBH_PORT_STR=$(sed -n '/^server:/,/^[^ ]/{/^ \+address:/{s/address:.*/http: '$PBH_WEBUI_PORT'/p}}' $PBH_CFG)
	sed '/^server:/a\'"$PBH_PORT_STR"'' -i $PBH_CFG
fi

# 初始化 PeerBanHelper 下载器
[ $(grep '^client: *$' $PBH_CFG) ] || echo client: >>$PBH_CFG
[ $(sed -n '/^client:/,/^[^ ]/{/^ \+BitCometDocker:/p}' $PBH_CFG) ] || {
echo PeerBanHelper 未配置本机 BitComet，执行初始化 | LOG
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
sed '/^client:/r/tmp/PBH_CLIENT_STR' -i $PBH_CFG ;}
PBH_CLIENT_SPACE=$(sed -n '/^client:/,/^[^ ]/{/^ \+BitCometDocker:/p}' $PBH_CFG | grep -o '^ \+')
[ "$(sed -n '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{/: \+'$WEBUI_USERNAME' *$/p}' $PBH_CFG)" ] || (
echo PeerBanHelper 配置中的本机 BitComet WebUI 用户名不正确，执行更正 | LOG
if [ "$(sed -n '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{/^ \+username:/p}' $PBH_CFG)" ]; then
	sed '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{s/username:.*/username: '$WEBUI_USERNAME'/}' -i $PBH_CFG
else
	PBH_CLIENT_USERNAME_STR=$(sed -n '/^client:/,/^[^ ]/{/^ \+type:/{s/type:.*/username: '$WEBUI_USERNAME'/p}}' $PBH_CFG)
	sed '/^ \+BitCometDocker:/a\'"$PBH_CLIENT_USERNAME_STR"'' -i $PBH_CFG
fi )
[ "$(sed -n '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{/: \+'$WEBUI_PASSWORD' *$/p}' $PBH_CFG)" ] || (
echo PeerBanHelper 配置中的本机 BitComet WebUI 密码不正确，执行更正 | LOG
if [ "$(sed -n '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{/^ \+password:/p}' $PBH_CFG)" ]; then
	sed '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{s/password:.*/password: '$WEBUI_PASSWORD'/}' -i $PBH_CFG
else
	PBH_CLIENT_PASSWORD_STR=$(sed -n '/^client:/,/^[^ ]/{/^ \+type:/{s/type:.*/password: '$WEBUI_PASSWORD'/p}}' $PBH_CFG)
	sed '/^ \+BitCometDocker:/a\'"$PBH_CLIENT_PASSWORD_STR"'' -i $PBH_CFG
fi )
[ $(sed -n '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{/'endpoint'/p}' $PBH_CFG | grep -oE :$BITCOMET_WEBUI_PORT/?$) ] || (
echo PeerBanHelper 配置中的本机 BitComet WebUI 地址不正确，执行更正 | LOG
if [ "$(sed -n '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{/^ \+endpoint:/p}' $PBH_CFG)" ]; then
	sed '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{s,endpoint:.*,endpoint: http://127.0.0.1:'$BITCOMET_WEBUI_PORT',}' -i $PBH_CFG
else
	PBH_CLIENT_ENDPOINT_STR=$(sed -n '/^client:/,/^[^ ]/{/^ \+type:/{s,type:.*,endpoint: http://127.0.0.1:'$BITCOMET_WEBUI_PORT',p}}' $PBH_CFG)
	sed '/^ \+BitCometDocker:/a\'"$PBH_CLIENT_ENDPOINT_STR"'' -i $PBH_CFG
fi )

# 初始化 BitComet BT 端口
[ $BITCOMET_BT_PORT ] || \
export BITCOMET_BT_PORT=$(grep ListenPort $BC_CFG | grep -oE '>.*<' | tr -d '><')
if [ $BITCOMET_BT_PORT ]; then
	if [ $(echo $BITCOMET_BT_PORT | grep -E '^[0-9]+$') ] && [ $BITCOMET_BT_PORT -le 65535 ]; then
		[ $BITCOMET_BT_PORT -ge 1024 ] || echo BitComet BT 端口指定为 1024 以下，可能无法监听 | LOG
		BC_BT_PORT_ORIG=$BITCOMET_BT_PORT
	else
		echo BitComet BT 端口指定错误，仅接受 65535 以下数字，执行初始化 | LOG
		BC_BT_PORT_FLAG=1
	fi
else
	echo BitComet BT 端口未指定，执行初始化 | LOG
	BC_BT_PORT_FLAG=1
fi
[ $BC_BT_PORT_FLAG ] && export BITCOMET_BT_PORT=6082
while (>/dev/tcp/127.0.0.1/$BITCOMET_BT_PORT) 2>/dev/null; do
	export BITCOMET_BT_PORT=$(shuf -i 1024-65535 -n 1)
	BC_BT_PORT_SHUF=1
done
if [ $BC_BT_PORT_FLAG ] || [ ! $BC_BT_PORT_SHUF ]; then
	echo BitComet 当前 BT 端口为 $BITCOMET_BT_PORT | LOG
else
	echo BitComet BT 端口 $BC_BT_PORT_ORIG 被占用，当前端口为 $BITCOMET_BT_PORT | LOG
fi

# 执行 NATMap 及 BitComet
rm -f /BitComet/DockerSTUNPORT
if [ "STUN" = 0 ]; then
	echo 已禁用 STUN，直接执行 BitComet | LOG
	/files/BitComet/bin/bitcometd &
else
	echo 已启用 STUN，BitComet BT 端口 $BITCOMET_BT_PORT 将作为 NATMap 的绑定端口 | LOG
	[ $StunServer ] || StunServer=turn.cloudflare.com
	[ $StunHttpServer ] || StunHttpServer=qq.com
	[ $StunInterval ] || StunInterval=25
	[ $StunInterface ] && StunInterface='-i '$StunInterface''
	[ $StunUdp ] && StunUdp='-u'
	if [ $StunForward ]; then
		[ $StunForwardAddr ] || StunForwardAddr=127.0.0.1
		StunForward='-t 127.0.0.1 -p '$BITCOMET_BT_PORT''
		echo 已启用 STUN 转发，目标为 127.0.0.1:$BITCOMET_BT_PORT
	fi
	NatmapStart='natmap '$StunArgs' -d -4 -s '$StunServer' -h '$StunHttpServer' -b '$BITCOMET_BT_PORT' -k '$StunInterval' '$StunInterface' '$StunForward' '$StunUdp' -e /files/natmap.sh'
	echo 本次 NATMap 执行命令
	echo $NatmapStart
	eval $NatmapStart
fi

# 执行 PeerBanHelper
if [ "$PBH" = 0 ]; then
	echo 已禁用 PeerBanHelper | LOG
	exec sh
else
	echo 执行 PeerBanHelper | LOG
	cd /PeerBanHelper
	exec java $JvmArgs -Dpbh.release=docker -Djava.awt.headless=true -Xmx512M -Xms16M -Xss512k -XX:+UseG1GC -XX:+UseStringDeduplication -XX:+ShrinkHeapInSteps -jar /files/PeerBanHelper/PeerBanHelper.jar
fi
