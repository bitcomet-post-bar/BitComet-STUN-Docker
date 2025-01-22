FROM wxhere/bitcomet-webui AS official

FROM alpine AS post-bar

COPY --from=official /root/BitCometApp /BitCometApp
