#!/bin/sh

# 初始化脚本日志
>/tmp/DockerLogs.log
LOG() { tee -a /tmp/DockerLogs.log ;}

echo 开始执行 BitComet 贴吧修改版 | LOG

# 检测环境
for DIR in BitComet Downloads PeerBanHelper; do
	mount | grep '/'$DIR' ' >/dev/null || (echo 未挂载 $DIR 目录 && WARN=1)
done

[ $WARN ] && echo 将在容器层上进行读写，性能较低且数据不持久
