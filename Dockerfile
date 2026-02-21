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

FROM chainguard/wolfi-base:latest@sha256:e735a9b94027e0d33e0056f94cfdca6d88adfbdf1ffa96bdbed0d43dc72fd179 AS test
RUN apk add --no-cache nushell bash curl
ENV PATH="/root/.local/bin:$PATH"
RUN curl -fsSL https://mise.run | MISE_INSTALL_PATH=/root/.local/bin/mise sh
WORKDIR /monorepo/plugins/sayt/
COPY . ./
RUN [ ! -e .mise.toml ] || nu sayt.nu setup
RUN nu sayt.nu test
RUN --network=none nu sayt.nu test
CMD ["true"]

FROM docker:29.2.0-cli@sha256:ae2609c051339b48c157d97edc4f1171026251607b29a2b0f25f990898586334 AS ci
USER root
WORKDIR /monorepo/plugins/sayt/
RUN apk add --no-cache socat curl
COPY --chmod=755 dind.sh /usr/local/bin/
COPY . ./
RUN (cd /tmp && /monorepo/plugins/sayt/sayt.sh --help) && ln -sf /root/.cache/sayt/mise-*/mise /usr/local/bin/mise
ENV PATH="/monorepo/plugins/sayt/stubs:/usr/local/bin:$PATH"
ENV MISE_TRUSTED_CONFIG_PATHS="/monorepo/plugins/sayt/.mise.toml"
ENV DOCKER_BUILDKIT=1
ENV COMPOSE_DOCKER_CLI_BUILD=1
ENV COMPOSE_BAKE=1
RUN --mount=type=secret,id=host.env,required dind.sh ./sayt.sh integrate --target integrate --progress plain
CMD ["true"]

FROM ci AS integrate
