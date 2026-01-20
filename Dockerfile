FROM busybox:musl@sha256:03db190ed4c1ceb1c55d179a0940e2d71d42130636a780272629735893292223 AS selector
ARG TARGETPLATFORM
COPY zig-out/bin/sayt-linux-x64 /sayt-linux-amd64
COPY zig-out/bin/sayt-linux-arm64 /sayt-linux-arm64
COPY zig-out/bin/sayt-linux-armv7 /sayt-linux-armv7
RUN case "$TARGETPLATFORM" in \
      linux/amd64) cp /sayt-linux-amd64 /sayt ;; \
      linux/arm64) cp /sayt-linux-arm64 /sayt ;; \
      linux/arm/v7) cp /sayt-linux-armv7 /sayt ;; \
    esac && chmod +x /sayt

FROM scratch AS release
COPY --from=selector /sayt /sayt
ENTRYPOINT ["/sayt"]

FROM docker:29-cli@sha256:06a1ee7af01fecf797268686773f20d1410a8ef4da497144bd08001011b1fffa AS integrate
RUN apk add --no-cache socat nmap-ncat curl && \
    curl -fsSL https://github.com/ko1nksm/shdotenv/releases/download/v0.14.0/shdotenv -o /usr/local/bin/shdotenv && \
    chmod 755 /usr/local/bin/shdotenv
WORKDIR /monorepo/plugins/sayt/
COPY --chmod=755 plugins/devserver/dind.sh /usr/local/bin/
COPY plugins/sayt/. ./
RUN --mount=type=secret,id=host.env,required dind.sh docker compose up --build --exit-code-from integrate --attach-dependencies integrate
CMD ["true"]
