FROM wxhere/bitcomet-webui AS official

FROM stable-slim AS post-bar

COPY --from=official /root/BitCometApp /BitCometApp
