FROM busybox:stable-uclibc AS busybox
FROM wxhere/bitcomet-webui AS official
FROM gcr.io/distroless/base-nossl-debian12 AS release
COPY --from=busybox /bin/sh /bin/sh
COPY --from=busybox /bin/ls /bin/ls
COPY --from=official /lib/*-linux-gnu/libz.so.1 /lib/libz.so.1
COPY --from=official /root/BitCometApp/usr /BitComet
ENV LANG=C.UTF-8
CMD ["/BitComet/bin/bitcometd"]
