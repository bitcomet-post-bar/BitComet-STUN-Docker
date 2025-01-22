mkdir -p /files

apk add curl jq unzip

# 下载 NATMap，识别对应的指令集架构
ARCH=$(cat etc/apk/arch)
case $ARCH in
  x86_64) DL=x86_64;;
  aarch64) DL=arm64;;
esac
wget https://github.com/heiher/natmap/releases/latest/download/natmap-linux-$DL -O /files/natmap

# 下载 PeerBanHelper
VER=$(curl -s https://api.github.com/repos/PBH-BTN/PeerBanHelper/releases/latest | jq -r '.tag_name' | sed 's/^v//')
wget https://github.com/PBH-BTN/PeerBanHelper/releases/download/v${VER}/PeerBanHelper_${VER}.zip -O PBH.zip
unzip PBH.zip -d /files

# 生成 PeerBanHelper 的 JRE
for JAR in $(find /files/PeerBanHelper | grep .jar); do jdeps --multi-release 23 $JAR >>/tmp/DEPS; done
DEPS=$(cat /tmp/DEPS | awk '{print$NF}' | grep -E '^(java|jdk)\.' | sort | uniq | tr '\n' ',' | sed 's/,$//)
jlink --no-header-files --no-man-pages --compress=zip-9 --strip-debug --add-modules $DEPS --output /files/PeerBanHelper/jre
