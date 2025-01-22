FROM wxhere/bitcomet-webui AS official

FROM alpine AS post-bar

COPY --from=official /root/BitCometApp /BitCometApp
ADD https://github.com/sgerrand/alpine-pkg-glibc/releases/download/2.35-r1/glibc-2.35-r1.apk glibc.apk

# RUN apk add glibc.apk --allow-untrusted \
#    && rm glibc.apk \
#    && rm -rf /var/cache/apk
