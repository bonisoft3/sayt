---
name: sayt-cnt
description: >
  How to write Dockerfile + compose.yaml for sayt launch / integrate —
  the service convention, multi-stage targets, multi-platform sha256 pinning,
  dind helpers.
  Use when containerizing a project or writing integration tests in containers.
user-invocable: false
---

# launch / integrate — Docker Compose

`sayt launch` starts a containerized dev environment. `sayt integrate` runs integration tests in containers. Both use Docker Compose with a specific service convention.

## How It Works

**`sayt launch`**:
1. `docker compose down -v --timeout 0 --remove-orphans` (clean slate)
2. Sets up Docker-in-Docker with a socat proxy
3. `docker compose run --build --service-ports launch`
4. Cleans up on exit

**`sayt integrate`**:
1. Clean slate + dind setup
2. `docker compose up integrate --abort-on-container-failure --exit-code-from integrate --force-recreate --build --renew-anon-volumes --remove-orphans --attach-dependencies`
3. On success: clean up. On failure: **leaves containers running** so you can `docker compose logs` and `docker compose down -v` manually.

## The compose.yaml Convention

Two services are required: `launch` and `integrate`.

```yaml
services:
  launch:
    command: ./gradlew dev -t           # your dev command
    ports: ["8080:8080"]
    build:
      network: host
      context: ../..                    # monorepo root, or "." for standalone
      dockerfile: services/myapp/Dockerfile
      secrets: [host.env]
      target: debug                     # Dockerfile stage for dev
    volumes:
      - //var/run/docker.sock:/var/run/docker.sock
    entrypoint: [/monorepo/plugins/devserver/dind.sh]
    secrets: [host.env]
    network_mode: host

  integrate:
    command: "true"                     # overridden by Dockerfile CMD
    build:
      network: host
      context: ../..
      dockerfile: services/myapp/Dockerfile
      secrets: [host.env]
      target: integrate                 # Dockerfile stage for integration tests

secrets:
  host.env:
    environment: HOST_ENV               # injected by sayt's dind helper
```

The `HOST_ENV` secret contains Docker credentials, Kubernetes config, and dind connection info.

`network_mode: host` on `launch` means services reach each other via `localhost`, testcontainers talks back to the host Docker daemon, and there are no port-mapping conflicts. On Linux this is native; Docker Desktop emulates it on macOS.

## Pinning Base Images

**Always pin base images to a multi-platform sha256 digest.** Tags drift — the same `node:22` can resolve to different bits on different days, and a tag that was multi-arch yesterday can silently lose a platform tomorrow. A digest-pinned manifest list is the only way to guarantee every host (arm64 Macs, amd64 CI, Graviton) pulls the same image.

### Fetching a Manifest-List Digest

```bash
docker buildx imagetools inspect node:22
```

Look for `Name: docker.io/library/node:22@sha256:<digest>`. That top-level digest is the manifest list — the one you want. The per-arch digests in the `Manifests:` section cover **one arch only** — do not use those.

Verify it covers the platforms you need:

```bash
docker buildx imagetools inspect node:22 --raw | jq '.manifests[] | .platform'
# Expect at least:
#   {"architecture":"amd64","os":"linux"}
#   {"architecture":"arm64","os":"linux"}
```

Then pin:

```dockerfile
FROM node:22@sha256:d53eaf0d... AS debug
```

```yaml
services:
  postgres:
    image: postgres:16@sha256:bb9ef9d4...
```

When you bump a tag, re-run `imagetools inspect`, verify the new digest is still a manifest list covering the same platforms, and update `FROM` / `image:` lines in one commit.

### Image Choice

- **Use official language images** — `eclipse-temurin:21`, `node:22`, `python:3.13-slim-bookworm`, `elixir:1.18-slim`, `ruby:3.3-slim-bookworm`, `mcr.microsoft.com/dotnet/sdk:10.0`.
- **Avoid niche community images** — They may lack multi-arch support. Install tools not in the base (e.g., sbt) in a `RUN` step from the official release URL.
- **Prefer slim/distroless for production** — `-slim-bookworm` variants cut size; add dev packages only as needed.

## Dockerfile Multi-Stage Pattern

sayt expects Dockerfiles with at least two targets: `debug` (used by `launch`) and `integrate` (used by `integrate`, extends `debug`).

```dockerfile
FROM node:22@sha256:... AS debug
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile
COPY . .
CMD ["pnpm", "dev"]

FROM debug AS integrate
CMD ["pnpm", "test:int", "--run"]
```

### Canonical Examples

**JVM (Gradle):**

```dockerfile
FROM eclipse-temurin:21@sha256:... AS debug
WORKDIR /app
COPY gradlew gradle.properties settings.gradle.kts build.gradle.kts ./
COPY gradle/ gradle/
RUN ./gradlew dependencies
COPY src/main/ src/main/
RUN ./gradlew assemble

FROM debug AS integrate
COPY src/it/ src/it/
CMD ["./gradlew", "integrationTest"]
```

**Python (uv):**

```dockerfile
FROM python:3.13-slim-bookworm@sha256:... AS debug
RUN pip install uv
WORKDIR /app
COPY . .
RUN uv sync                              # install + lockfile verification in one step
CMD ["uv", "run", "flask", "run"]

FROM debug AS integrate
CMD ["uv", "run", "pytest", "-v", "--tb=short"]
```

**Rust:**

```dockerfile
FROM rust:1-bookworm@sha256:... AS debug
WORKDIR /app
COPY . .                                 # Rust build scripts often read arbitrary files
RUN cargo build --locked
CMD ["cargo", "run", "--locked"]

FROM debug AS integrate
CMD ["cargo", "test", "--locked"]
```

### Patterns By Language Family

Everything not above follows the same recipe: copy dependency manifests, install deps (leveraging Docker layer caching), copy the rest, build, set a `debug` CMD, then extend with an `integrate` CMD. The only per-language deltas worth knowing:

| Language | Dep manifest | Install command | Notes |
|---|---|---|---|
| **Node (pnpm)** | `package.json` + `pnpm-lock.yaml` | `corepack enable && pnpm install --frozen-lockfile` | — |
| **Node (bun)** | `package.json` + `bun.lock*` | `bun install --frozen-lockfile` | Use `Dockerfile.sayt` if devcontainer owns `Dockerfile` |
| **Maven** | all `pom.xml` files + parent poms | `mvn dependency:go-offline -pl <mod> -am -q \|\| true` | `-pl <module> -am` for multi-module |
| **Elixir** | `mix.exs` + `mix.lock` | `mix local.hex --force && mix local.rebar --force && mix deps.get && mix deps.compile` | Slim needs `build-essential` + `ca-certificates` |
| **.NET** | `.sln`, `Directory.Build.props`, `global.json`, all `.csproj` | `dotnet restore` | Official multi-arch `mcr.microsoft.com/dotnet/sdk:10.0` |
| **Scala (sbt)** | `build.sbt` + `project/` | Install sbt via curl tarball; `sbt update \|\| true` | Don't use niche `sbtscala/scala-sbt` images — no arm64 |
| **Ruby** | `Gemfile` + all `*.gemspec` | `bundle install` | Slim needs `build-essential libssl-dev libyaml-dev pkg-config` |
| **C / autotools** | — | `apt install build-essential autoconf libtool`; chain `autoreconf -i && ./configure && make -j$(nproc)` in one RUN | `git submodule update --init` if submodules are vendored |

When adapting an existing project that already has a Dockerfile with its own stage names (`shell`, `dev`, `test`, `integration-test`, etc.), map `target:` to the real stage names instead of renaming them, and add `privileged: true` if the existing tests use BuildKit or testcontainers:

```yaml
services:
  launch:
    build: { context: ., dockerfile: Dockerfile, target: shell }
    privileged: true
  integrate:
    build: { context: ., dockerfile: Dockerfile, target: integration-test }
    privileged: true
```

## Docker-in-Docker Support

sayt provides dind helpers for scenarios where containers need to talk to Docker (testcontainers, BuildKit):

1. A socat container proxies the Docker socket over TCP.
2. `DOCKER_HOST`, `TESTCONTAINERS_HOST_OVERRIDE`, and `DOCKER_AUTH_CONFIG` are injected.
3. All dind connection info is passed as the `host.env` build secret.

This lets testcontainers create sibling containers on the host daemon.

## Writing Good compose.yaml for sayt

1. **Define both `launch` and `integrate`.** These are the services sayt expects.
2. **Use `target:` in build.** Map to Dockerfile stages, not the default.
3. **Set `context:` to the monorepo root.** Usually `../..` from a service dir.
4. **Include the `host.env` secret.** Required for dind and credential forwarding.
5. **`network_mode: host` on `launch`.** Simplifies networking.
6. **`command: "true"` on `integrate`.** Let the Dockerfile CMD handle execution.
7. **Pin every image with a manifest-list sha256.** Both `FROM` lines and `image:` lines in compose.

## Current flags

Run `sayt help launch` and `sayt help integrate` for current flags.
