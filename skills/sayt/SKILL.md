---
name: sayt-lifecycle
description: >
  Unified development lifecycle tool. Use when the user asks about building,
  testing, setting up, deploying, or configuring a development environment.
  Teaches how to write and fix the configuration files behind each verb
  and how to configure sayt itself.
allowed-tools: Bash(sayt:*)
---

# sayt-lifecycle — Unified Development Lifecycle

sayt is a small CLI that provides consistent verbs for the entire software development lifecycle. It reuses configuration you already have (`.mise.toml`, `.vscode/tasks.json`, `.say.yaml`, `compose.yaml`, `skaffold.yaml`, `.goreleaser.yaml`) so there is zero drift between your IDE, CI, and terminal.

## The Real Verbs

The complete, definitive list:

| Verb pair | Layer | Underlying tools | Config file |
|-----------|-------|------------------|-------------|
| `sayt setup` / `sayt doctor` | Toolchain | [mise](https://mise.jdx.dev/) | `.mise.toml` + `mise.lock` |
| `sayt generate` / `sayt lint` | Static | [CUE](https://cuelang.org/), [gomplate](https://gomplate.ca/), plus any static checker | `.say.cue` / `.say.yaml` |
| `sayt build` / `sayt test` | App | whatever your language uses, via VS Code tasks | `.vscode/tasks.json` |
| `sayt launch` / `sayt integrate` | Stack (containers) | [docker compose](https://docs.docker.com/compose/) | `Dockerfile` + `compose.yaml` |
| `sayt release` / `sayt verify` | Public | [goreleaser](https://goreleaser.com/) + [skaffold](https://skaffold.dev/) | `.goreleaser.yaml` / `skaffold.yaml` |

**Anything else is not a sayt verb.** If someone tells you to run `sayt <anything-not-above>`, it's wrong. Verbs sayt does not have:

| Non-verb | What the user probably wants |
|---|---|
| `vet` | `lint` — `vet` was superseded by `lint` |
| `preview` | `skaffold dev -p preview` directly |
| `stage` | `skaffold run -p staging` directly |
| `publish` | `release` (make work public via goreleaser) |
| `setup-butler` | `setup` — `setup-butler` never existed as a stable verb |
| `develop` | `launch` (containerized dev) or `build`/`test` (app dev) |
| `loadtest` | `verify` customized with a load test step |
| `observe` | Direct tool invocation (`kubectl logs`, `docker compose logs`, etc.) |

The verbs don't need to cover every use case. When a real verb doesn't fit, the agent is free to either:

1. **Customize the verb** — edit `.say.yaml`, `.vscode/tasks.json`, `compose.yaml`, `.goreleaser.yaml`, etc. so the existing verb covers the new case. Prefer this when the case is reusable.
2. **Use a direct command** — `skaffold dev -p preview`, `docker compose logs`, `kubectl exec`, `mise exec -- <tool>`, etc. Prefer this for one-off investigation.

## Seven-Environment Model

sayt organizes the development lifecycle into seven environments, each adding a layer of confidence. Run `sayt doctor` to see which ones are ready:

1. **pkg** — Package manager (mise). Tools installed and available.
2. **cli** — CLI tools (cue, gomplate). Code generation and validation work.
3. **ide** — IDE integration (CUE + `.vscode/tasks.json`). Build and test tasks run from your editor.
4. **cnt** — Container (docker). Code runs identically across machines.
5. **k8s** — Kubernetes (kind, skaffold). Full-stack preview deployments work.
6. **cld** — Cloud (gcloud). Staging deployment is live.
7. **xpl** — Crossplane. Production infrastructure is managed as code.

## How sayt Reuses Existing Config

sayt does **not** invent new configuration formats. It delegates:

- **`.mise.toml`** + **`mise.lock`** — `sayt setup` runs `mise install`.
- **`.vscode/tasks.json`** — `sayt build` and `sayt test` extract and run labels via CUE.
- **`.say.yaml` / `.say.cue`** — override any verb with custom commands; declarative lint rules (`#copy`, `#shared`, `#vet`).
- **`compose.yaml`** — `sayt launch` runs `docker compose run --build --service-ports launch`. `sayt integrate` runs `docker compose up integrate`.
- **`skaffold.yaml`** — `sayt verify` runs `skaffold verify`. For deploys, use `skaffold dev/run -p <profile>` directly.
- **`.goreleaser.yaml`** — `sayt release` runs goreleaser (often with `skaffold build --push` as a publisher).

## What `setup` Does and Does Not Do

`sayt setup` runs `mise install`. That is the entire job: install the tools declared in `.mise.toml`, pinned by `mise.lock`.

`setup` does **not**:

- Run `pnpm install`, `bundle install`, `pip install`, `go mod download`, `cargo fetch`, or any other project dependency manager
- Warm compiler caches
- Run migrations
- Pull base images

Those steps belong in:

- **The Dockerfile** — for container builds, do dependency installs as `RUN` steps so they cache properly
- **`Taskfile.yml` `deps:` entries** — for explicit local orchestration where one step needs another first

This keeps `setup` fast and idempotent: you run it when `.mise.toml` changes or on a clean checkout, and you never need it in the inner loop.

## The TDD Loop

Pick the verb pair for the layer your change actually lives in, ping-pong until green, then advance the cascade to test the next slower layer. Full details in the **sayt-tdd** skill.

Quick version:

```bash
# Pick your pair for the layer you're editing
sayt lint && sayt test         # app source code
sayt generate && sayt lint     # generated code
sayt lint && sayt launch       # docker / compose / config
sayt launch && sayt integrate  # multi-service behavior
sayt release && sayt verify    # publish + post-deploy checks

# Deploys use skaffold directly, not a sayt verb
skaffold dev -p preview
skaffold run -p staging
skaffold run -p production
```

No verb gates any other. `launch` doesn't need `test` green. `integrate` doesn't need `lint` green. `release` doesn't need `integrate` green.

## Per-Verb Skill Reference

For detailed guidance on writing the configuration file for each verb, see the per-verb skills: `sayt-cli`, `sayt-ide`, `sayt-code`, `sayt-cnt`, `sayt-k8s`. For a compact verb → tool → config card and troubleshooting by verb, see [reference.md](./reference.md).

## Current sayt help

Run `sayt help` for current flags and options.
