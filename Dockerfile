FROM debian:stable-slim AS libraries
FROM wxhere/bitcomet-webui AS official
FROM gcr.io/distroless/base-debian12:debug AS release
# COPY --from=libraries /lib/*-linux-gnu/libz.so.1 /lib/libz.so.1
# COPY --from=libraries /lib/*-linux-gnu/libpthread.so.0 /lib/libpthread.so.0
# COPY --from=libraries /lib/*-linux-gnu/libstdc++.so.6 /lib/libstdc++.so.6
# COPY --from=libraries /lib/*-linux-gnu/libgcc_s.so.1 /lib/libgcc_s.so.1
COPY --from=official /root/BitCometApp/usr /BitComet
ENV LANG=C.UTF-8
# CMD ["/BitComet/bin/bitcometd"]
