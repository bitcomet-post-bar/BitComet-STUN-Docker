FROM wxhere/bitcomet-webui AS builder
COPY builder.sh builder.sh
RUN sh builder.sh

FROM ubuntu:20.04 AS release
COPY --from=builder /files /files
COPY /files /files
ENV PATH="$PATH:/files:/files/PeerBanHelper/jre/bin" \
    LANG=C.UTF-8
RUN chmod +x /files/* && \
    apt-get update && \
    apt-get install -y miniupnpc && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir /root/.config && \
    ln -s /BitComet /root/.config/BitComet && \
    ln -s /Downloads /root/Downloads && \
    ln -s /PeerBanHelper /PBHDIR
VOLUME /tmp
CMD ["start.sh"]

LABEL org.opencontainers.image.source="https://github.com/bitcomet-post-bar/BitComet-STUN-Docker" \
      org.opencontainers.image.description="BitComet by Post-Bar (unofficial mod)"
