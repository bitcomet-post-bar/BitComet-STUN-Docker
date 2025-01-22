FROM bellsoft/liberica-runtime-container:jdk-23-musl AS builder

COPY builder.sh builder.sh

RUN sh builder.sh

FROM wxhere/bitcomet-webui AS release

COPY --from=builder /files /files
COPY /files /files
ENV PATH="$PATH:/files:/files/PeerBanHelper/jre/bin"

RUN chmod +x /files/*

CMD ["start.sh"]

LABEL org.opencontainers.image.source="https://github.com/bitcomet-post-bar/BitComet-STUN-Docker"
LABEL org.opencontainers.image.description="Unofficial BitComet by Post-Bar"
