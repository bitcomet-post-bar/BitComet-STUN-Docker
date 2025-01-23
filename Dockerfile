FROM busybox:stable-uclibc AS busybox
FROM wxhere/bitcomet-webui AS official
FROM gcr.io/distroless/cc-debian12 AS release
COPY --from=busybox /bin/sh /bin/sh
COPY --from=busybox /bin/ls /bin/ls
COPY --from=official /root/BitCometApp/usr /BitComet
ENV LANG=C.UTF-8
CMD ["/BitComet/bin/bitcometd"]
