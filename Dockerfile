FROM busybox:musl AS selector
ARG TARGETPLATFORM
COPY zig-out/bin/sayt-linux-x64 /sayt-linux-amd64
COPY zig-out/bin/sayt-linux-arm64 /sayt-linux-arm64
COPY zig-out/bin/sayt-linux-armv7 /sayt-linux-armv7
RUN case "$TARGETPLATFORM" in \
      linux/amd64) cp /sayt-linux-amd64 /sayt ;; \
      linux/arm64) cp /sayt-linux-arm64 /sayt ;; \
      linux/arm/v7) cp /sayt-linux-armv7 /sayt ;; \
    esac && chmod +x /sayt

FROM scratch
COPY --from=selector /sayt /sayt
ENTRYPOINT ["/sayt"]
