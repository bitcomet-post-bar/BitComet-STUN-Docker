FROM wxhere/bitcomet-webui AS builder
COPY builder.sh builder.sh
RUN sh builder.sh

FROM wxhere/bitcomet-webui AS release
COPY --from=builder /files /files
COPY /files /files
ENV PATH="$PATH:/files:/files/PeerBanHelper/jre/bin"
RUN chmod +x /files/* && \
    apt-get update && \
    apt-get install -y miniupnpc && \
    rm -rf /var/lib/apt/lists/*
CMD ["start.sh"]

LABEL org.opencontainers.image.source="https://github.com/bitcomet-post-bar/BitComet-STUN-Docker"
LABEL org.opencontainers.image.description="BitComet by Post-Bar (unofficial mod)"
