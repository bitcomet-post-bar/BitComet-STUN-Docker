FROM ubuntu AS builder
COPY builder.sh builder.sh
RUN sh builder.sh

FROM wxhere/bitcomet-webui AS official

# FROM debian:stable-slim AS release
FROM ubuntu AS release
COPY --from=builder /files /files
COPY --from=official /root/BitCometApp/usr/ /files/BitComet
COPY /files /files
ENV PATH="$PATH:/files:/files/PeerBanHelper/jre/bin" \
    LANG=C.UTF-8
RUN chmod +x /files/* && \
    apt-get update && \
    apt-get install -y miniupnpc nftables xxd socat openssl ca-certificates libevent-2.1-7t64 libevent-openssl-2.1-7t64 libevent-pthreads-2.1-7t64 && \
    rm -rf /var/lib/apt/lists/* && \
    useradd socat -u 50080 -d /nonexistent -s /usr/sbin/nologin && \
    useradd sslproxy -u 58443 -d /nonexistent -s /usr/sbin/nologin && \
    useradd bitcomet -u 56082 -g 0 -m -s /bin/bash && \
    mkdir /home/bitcomet/.config && \
    ln -s /BitComet /home/bitcomet/.config/BitComet && \
    ln -s /Downloads /home/bitcomet/Downloads && \
    mkdir /root/.config && \
    ln -s /BitComet /root/.config/BitComet && \
    ln -s /Downloads /root/Downloads
    # ln -s /PeerBanHelper /PBHDIR
ADD https://oniicyan.pages.dev/stun_servers_ipv4_rst.txt /files/StunServers.txt
ADD https://oniicyan.pages.dev/https_trackers.txt /files/HttpsTrackers.txt
ADD https://oniicyan.pages.dev/topsites.txt /files/SiteList.txt
CMD ["start.sh"]

LABEL org.opencontainers.image.source="https://github.com/bitcomet-post-bar/BitComet-STUN-Docker" \
      org.opencontainers.image.description="BitComet by Post-Bar (unofficial mod)"
