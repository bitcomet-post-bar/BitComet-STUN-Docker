FROM wxhere/bitcomet-webui AS official
FROM gcr.io/distroless/cc-debian12:latest AS cc
FROM alpine AS post-bar
COPY --from=official /root/BitCometApp /BitCometApp
COPY --from=cc --chmod=755 --chown=root:root /lib/*-linux-gnu/ld-linux-* /usr/local/lib/
