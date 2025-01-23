FROM busybox:stable-uclibc as busybox
FROM wxhere/bitcomet-webui AS official
FROM gcr.io/distroless/static-debian12 AS release
COPY --from=busybox /bin/sh /bin/sh
COPY --from=official /root/BitCometApp/usr /BitComet
ENV LANG=C.UTF-8
CMD ["/BitComet/bin/bitcometd"]
