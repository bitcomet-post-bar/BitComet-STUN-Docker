FROM gcr.io/distroless/cc-debian12 AS cc
FROM wxhere/bitcomet-webui AS official
FROM alpine AS release
COPY --from=cc --chmod=755 --chown=root:root /lib/*-linux-gnu/ld-linux-* /usr/local/lib/
COPY --from=official /root/BitCometApp/usr /BitComet
ENV LANG=C.UTF-8
# CMD ["/BitComet/bin/bitcometd"]
