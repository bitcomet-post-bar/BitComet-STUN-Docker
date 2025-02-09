FROM wxhere/bitcomet-webui AS builder
COPY builder.sh builder.sh
RUN sh builder.sh

# FROM debian:stable-slim AS release
FROM ubuntu AS release
COPY --from=builder /files /files
COPY /files /files
ENV PATH="$PATH:/files:/files/PeerBanHelper/jre/bin" \
    LANG=C.UTF-8
RUN chmod +x /files/* && \
    apt-get update && \
#   apt-get install -y miniupnpc nftables socat busybox && \
#   ln -s /bin/busybox /usr/bin/xxd && \
#   ln -s /bin/busybox /usr/bin/wget && \
    apt-get install -y miniupnpc nftables socat xxd wget && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir /root/.config && \
    ln -s /BitComet /root/.config/BitComet && \
    ln -s /PeerBanHelper /PBHDIR && \
    ln -s /Downloads /root/Downloads
# VOLUME /tmp
ADD https://oniicyan.pages.dev/stun_servers_ipv4_rst.txt /files
CMD ["start.sh"]

LABEL org.opencontainers.image.source="https://github.com/bitcomet-post-bar/BitComet-STUN-Docker" \
      org.opencontainers.image.description="BitComet by Post-Bar (unofficial mod)"
