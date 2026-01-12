FROM busybox:musl@sha256:e8f62bb9c8bc88ae66f935a1621ad13dbf1bb899ad5db1dd0e3c5cb21ae1a414 AS selector
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

FROM docker:27-cli@sha256:851f91d241214e7c6db86513b270d58776379aacc5eb9c4a87e5b47115e3065c AS integrate
RUN apk add --no-cache socat nmap-ncat curl && \
    curl -fsSL https://github.com/ko1nksm/shdotenv/releases/download/v0.14.0/shdotenv -o /usr/local/bin/shdotenv && \
    chmod 755 /usr/local/bin/shdotenv
WORKDIR /monorepo/plugins/sayt/
COPY --chmod=755 plugins/devserver/dind.sh /usr/local/bin/
COPY plugins/sayt/. ./
RUN --mount=type=secret,id=host.env,required dind.sh docker compose up --build --exit-code-from integrate --attach-dependencies integrate
CMD ["true"]
