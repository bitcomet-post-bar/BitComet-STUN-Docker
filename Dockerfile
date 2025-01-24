FROM gcr.io/distroless/cc-debian12 AS cc
FROM alpine AS distro
FROM wxhere/bitcomet-webui AS official
COPY --from=cc --chmod=755 --chown=root:root /lib/*-linux-gnu/ld-linux-* /usr/local/lib/
RUN mkdir -p /tmp/lib
RUN ln -s /usr/local/lib/ld-linux-* /tmp/lib/
FROM gcr.io/distroless/static-debian12 AS release
ENV LD_LIBRARY_PATH="/usr/local/lib"
COPY --from=cc --chmod=755 --chown=root:root /lib/*-linux-gnu/* /usr/local/lib/
COPY --from=distro --chmod=755 --chown=root:root /tmp/lib /lib
COPY --from=distro --chmod=755 --chown=root:root /tmp/lib /lib64
ENV LANG=C.UTF-8
COPY --from=official /root/BitCometApp/usr /BitComet
# CMD ["/BitComet/bin/bitcometd"]
