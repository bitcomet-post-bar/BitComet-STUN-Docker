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
    apt-get install -y miniupnpc nftables socat openssl ca-certificates sslsplit xxd && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir /root/.config && \
    ln -s /BitComet /root/.config/BitComet && \
    ln -s /PeerBanHelper /PBHDIR && \
    ln -s /Downloads /root/Downloads && \
    useradd -u 56082 bitcometd -d /var/run/bitcometd -s /bin/false && \
    useradd -u 58443 sslproxy -d /var/run/sslproxy -s /bin/false
ADD https://oniicyan.pages.dev/stun_servers_ipv4_rst.txt /files
CMD ["start.sh"]

LABEL org.opencontainers.image.source="https://github.com/bitcomet-post-bar/BitComet-STUN-Docker" \
      org.opencontainers.image.description="BitComet by Post-Bar (unofficial mod)"
