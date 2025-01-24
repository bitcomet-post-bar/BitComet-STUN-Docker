FROM debian:stable-slim AS distro
FROM wxhere/bitcomet-webui AS official
FROM gcr.io/distroless/base-debian12 AS release
COPY --from=distro --chmod=755 --chown=root:root /lib/*-linux-gnu/libz.so.1 /lib/libz.so.1
COPY --from=distro --chmod=755 --chown=root:root /lib/*-linux-gnu/libpthread.so.0 /lib/libpthread.so.0
COPY --from=distro --chmod=755 --chown=root:root /lib/*-linux-gnu/libstdc++.so.6 /lib/libstdc++.so.6
COPY --from=distro --chmod=755 --chown=root:root /lib/*-linux-gnu/libgcc_s.so.1 /lib/libgcc_s.so.1
COPY --from=distro /bin/sh /bin/sh
COPY --from=distro /bin/ls /bin/ls
COPY --from=official /root/BitCometApp/usr /BitComet
ENV LANG=C.UTF-8
CMD ["/BitComet/bin/bitcometd"]
