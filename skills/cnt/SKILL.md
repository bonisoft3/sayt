---
name: sayt-cnt
description: >
  How to write Dockerfile + compose.yaml — the develop/integrate service
  convention, multi-stage targets, dind helpers.
  Use when containerizing a project, writing docker compose services, or setting up integration tests.
user-invocable: false
---

# launch / integrate — Docker Compose Containerization

`sayt launch` starts a containerized development environment. `sayt integrate` runs integration tests in containers. Both use Docker Compose with a specific service convention.

## How It Works

### `sayt launch`

1. Cleans up any leftover containers: `docker compose down -v --timeout 0 --remove-orphans`
2. Sets up Docker-in-Docker (dind) environment with a socat proxy
3. Runs: `docker compose run --build --service-ports develop`
4. Cleans up the socat container on exit

### `sayt integrate`

1. Cleans up: `docker compose down -v --timeout 0 --remove-orphans`
2. If `--no-cache`: builds without Docker layer cache first
3. Sets up dind environment
4. Runs: `docker compose up integrate --abort-on-container-failure --exit-code-from integrate --force-recreate --build --renew-anon-volumes --remove-orphans --attach-dependencies`
5. On success: cleans up containers
6. On failure: **leaves containers running** for inspection (run `docker compose logs` or `docker compose down -v` when done)

## The compose.yaml Convention

sayt expects two services in `compose.yaml`:

### `develop` service (for `sayt launch`)

The development service runs your app with hot reload, debugging, port mapping, etc.

```yaml
services:
  develop:
    command: ./gradlew dev -t          # Your dev command
    ports:
      - "8080:8080"                    # Expose ports to host
    build:
      network: host
      context: ../..                   # Monorepo root (or ".")
      dockerfile: services/myapp/Dockerfile
      secrets:
        - host.env
      target: debug                    # Dockerfile stage for dev
    volumes:
      - //var/run/docker.sock:/var/run/docker.sock
    entrypoint:
      - /monorepo/plugins/devserver/dind.sh
    secrets:
      - host.env
    network_mode: host
```

### `integrate` service (for `sayt integrate`)

The integration service runs your test suite in an isolated container.

```yaml
services:
  integrate:
    command: "true"                    # Overridden by Dockerfile CMD
    build:
      network: host
      context: ../..
      dockerfile: services/myapp/Dockerfile
      secrets:
        - host.env
      target: integrate               # Dockerfile stage for integration
```

### Secrets

```yaml
secrets:
  host.env:
    environment: HOST_ENV             # Injected by sayt's dind helper
```

The `HOST_ENV` secret contains Docker credentials, Kubernetes config, and dind connection info.

## Dockerfile Multi-Stage Pattern

sayt expects Dockerfiles with at least two targets:

### `debug` target (used by `develop`)

Contains the full development environment with source code, tools, and hot reload:

```dockerfile
FROM node:22 AS debug
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN pnpm install
COPY . .
CMD ["pnpm", "dev"]
```

### `integrate` target (used by `integrate`)

Extends debug with integration test execution:

```dockerfile
FROM debug AS integrate
COPY tests/ tests/
CMD ["pnpm", "test:int"]
```

### Full Multi-Stage Example (JVM)

```dockerfile
# Base with tools
FROM eclipse-temurin:21 AS debug
WORKDIR /app
COPY gradlew gradlew.bat gradle.properties settings.gradle.kts build.gradle.kts ./
COPY gradle/ gradle/
RUN ./gradlew dependencies
COPY src/main/ src/main/
COPY .vscode/ .vscode/
RUN ./gradlew assemble
COPY src/test/ src/test/

# Integration tests
FROM debug AS integrate
COPY src/it/ src/it/
CMD ["./gradlew", "integrationTest"]
```

### Full Multi-Stage Example (Node.js)

```dockerfile
FROM node:22 AS debug
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile
COPY . .
RUN pnpm build
CMD ["pnpm", "dev"]

FROM debug AS integrate
CMD ["pnpm", "test:int", "--run"]
```

### Full Multi-Stage Example (Python / uv)

```dockerfile
FROM python:3.13-slim-bookworm AS debug
RUN pip install uv
WORKDIR /app
COPY . .
RUN uv sync
CMD ["uv", "run", "flask", "run"]

FROM debug AS integrate
CMD ["uv", "run", "pytest", "-v", "--tb=short"]
```

Key considerations for Python projects:
- **`uv sync`** — Installs all dependencies from `pyproject.toml` + `uv.lock`
- **`python:3.x-slim-bookworm`** — Slim Debian image keeps the container small
- **No separate install step** — `uv sync` handles both install and lockfile verification

### Full Multi-Stage Example (Bun / TypeScript)

```dockerfile
FROM oven/bun:1.2.20 AS debug
WORKDIR /app
COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile
COPY . .
CMD ["bun", "run", "dev"]

FROM debug AS integrate
RUN bun run build
CMD ["bun", "run", "test"]
```

Key considerations for Bun projects:
- **`bun.lock*`** — The glob ensures the build doesn't fail if there's no lockfile yet
- **`--frozen-lockfile`** — Ensures reproducible installs
- **Build in integrate** — Run `bun run build` in the integrate stage to verify the build compiles before testing
- **Naming conflicts** — If the project already has a `Dockerfile` (e.g., devcontainer), name yours `Dockerfile.sayt` and set `dockerfile: Dockerfile.sayt` in compose.yaml

### Full Multi-Stage Example (Java / Maven)

```dockerfile
FROM maven:3.9-eclipse-temurin-21 AS debug
WORKDIR /app
COPY pom.xml ./
COPY module-a/pom.xml module-a/
COPY module-b/pom.xml module-b/
RUN mvn dependency:go-offline -pl module-a -am -q || true
COPY . .
RUN mvn compile -pl module-a -am -q
CMD ["mvn", "exec:java", "-pl", "module-a"]

FROM debug AS integrate
CMD ["mvn", "test", "-pl", "module-a", "-am"]
```

Key considerations for Java/Maven projects:
- **Copy all `pom.xml` files first** — For multi-module projects, copy each module's `pom.xml` before running `dependency:go-offline` to leverage Docker layer caching
- **`dependency:go-offline || true`** — Downloads dependencies for caching; `|| true` because some plugins may fail during offline resolution
- **`-pl <module> -am`** — Build only the target module and its dependencies, not the entire reactor
- **`maven:3.x-eclipse-temurin-21`** — Official Maven image includes JDK; no need to install separately

### Full Multi-Stage Example (Rust)

```dockerfile
FROM rust:1-bookworm AS debug
WORKDIR /app
COPY . .
RUN cargo build --locked
CMD ["cargo", "run", "--locked"]

FROM debug AS integrate
CMD ["cargo", "test", "--locked"]
```

Key considerations for Rust projects:
- **Use `COPY . .`** — Rust build scripts (`build.rs`) often read arbitrary source files, asset directories, and config files at compile time. Selective `COPY` of only `Cargo.toml`/`src/` will fail if the build script references other paths. Prefer copying everything and using `.dockerignore` to exclude `target/`.
- **Cargo cache volumes** — Mount a named volume at `/usr/local/cargo/registry` in compose.yaml to cache downloaded crates across builds
- **`--locked`** — Ensures the container uses the exact versions from `Cargo.lock`

## Docker-in-Docker (dind) Support

sayt provides dind helpers for scenarios where containers need to talk to Docker (e.g., testcontainers):

1. **socat proxy** — A socat container is started to proxy the Docker socket over TCP
2. **Environment variables** — `DOCKER_HOST`, `TESTCONTAINERS_HOST_OVERRIDE`, and `DOCKER_AUTH_CONFIG` are injected
3. **host.env secret** — All dind connection info is passed as a build secret

This enables testcontainers-based integration tests to create sibling containers.

## Host Networking

sayt services use `network_mode: host` by default. This means:
- Services can reach each other via `localhost`
- No port mapping conflicts
- Testcontainers can connect back to the host Docker daemon
- Works on Linux natively; on macOS, Docker Desktop provides host networking emulation

## Complete compose.yaml Example

```yaml
volumes:
  root-dot-docker-cache-mount: {}

services:
  develop:
    command: ./gradlew dev -t
    ports:
      - "8080:8080"
    build:
      network: host
      context: ../..
      dockerfile: services/tracker/Dockerfile
      secrets:
        - host.env
      target: debug
    volumes:
      - //var/run/docker.sock:/var/run/docker.sock
      - ${HOME:-~}/.skaffold/cache:/root/.skaffold/cache
    entrypoint:
      - /monorepo/plugins/devserver/dind.sh
    secrets:
      - host.env
    network_mode: host

  integrate:
    command: "true"
    build:
      network: host
      context: ../..
      dockerfile: services/tracker/Dockerfile
      secrets:
        - host.env
      target: integrate

secrets:
  host.env:
    environment: HOST_ENV
```

## Cleanup Behavior

- **Success**: `sayt integrate` automatically runs `docker compose down -v` to clean up
- **Failure**: Containers are **left running** so you can inspect logs:
  ```bash
  docker compose logs          # View all logs
  docker compose logs integrate # View integration service logs
  docker compose down -v       # Clean up manually when done
  ```

## Adapting to Existing Dockerfiles

When a project already has a multi-stage Dockerfile with its own stage naming conventions, map `target:` to the actual stage names rather than the default `debug`/`integrate`:

```yaml
services:
  develop:
    build:
      context: .
      dockerfile: Dockerfile
      target: shell              # Use whatever dev/shell stage exists
    privileged: true

  integrate:
    build:
      context: .
      dockerfile: Dockerfile
      target: integration-test   # Use the project's actual test stage
    privileged: true
```

Key considerations:
- **`privileged: true`** — Required when integration tests run Docker-in-Docker (e.g., BuildKit, testcontainers)
- **Stage names vary** — Projects may use `shell`, `dev`, `test`, `integration-test`, etc. Check the Dockerfile for available `AS <name>` stages
- **Existing build systems** — If the project builds via `docker buildx bake`, the compose.yaml `integrate` service complements (not replaces) that workflow

## Writing Good Compose Files for sayt

1. **Always define `develop` and `integrate`** — These are the services sayt expects
2. **Use `target:` in build** — Map to the Dockerfile stages for dev and integration
3. **Set `context` to monorepo root** — Usually `../..` from a service directory, or `.` for standalone projects
4. **Include the `host.env` secret** — Required for dind and credential forwarding
5. **Use `network_mode: host`** for develop — Simplifies networking
6. **Set `command: "true"` for integrate** — Let the Dockerfile CMD handle execution

## Current flags

!`sayt help launch`
!`sayt help integrate`
