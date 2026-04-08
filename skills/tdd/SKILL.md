---
name: sayt-tdd
description: >
  The TDD loop for sayt projects. Use when implementing features,
  fixing bugs, or diagnosing failures. Teaches how to pick the verb
  pair that gives fastest feedback at the current layer, ping-pong
  inside that layer until green, then advance the cascade.
user-invocable: false
---

# TDD Loop — Problem-Driven Ping-Pong, Cascade Advancement

sayt verbs are **independent tools for different layers**. No verb gates any other. `launch` doesn't require `test` green; `integrate` doesn't require `lint` green. The loop is not a pipeline you walk end-to-end — it's a two-phase rhythm:

1. **Ping-pong inside a layer.** Pick the verb pair that reproduces the current problem fastest. Iterate between them until the problem converges and the layer is green.
2. **Advance the cascade.** Once the current layer is green, run the next slower layer to surface anything that only reproduces there. If it fails, drop back down to wherever the failure reproduces fastest, fix it, then advance again.

You do not progress through every verb in sequence. You walk the cascade until failures stop appearing at slower layers.

## The Layers

| Layer | Verb pair | Feedback time | What it exercises |
|---|---|---|---|
| **Toolchain** | `setup` / `doctor` | seconds | `mise install` + environment-tier check |
| **Static** | `generate` / `lint` | seconds | Code generation, type-check, app linters, config validation |
| **App** | `build` / `test` | seconds | Compile + unit tests for the app only (no docker, no network) |
| **Stack** | `launch` / `integrate` | minutes | Full stack in `docker compose` — multi-service runtime behavior |
| **Public** | `release` / `verify` | minutes to 10+ | Publish artifacts (goreleaser, often delegating to skaffold build) + post-deploy checks |

## Picking the Verb Pair

Pick the pair that iterates fastest on the problem in front of you. Examples:

| Working on… | Fastest pair |
|---|---|
| App source code (components, routes, lib) | `lint` ↔ `test` |
| Linter config / tsconfig / eslint rules | `lint` (alone) |
| Generated code (CUE, gomplate, protobuf) | `generate` ↔ `lint` |
| Dockerfile, compose.yaml, Caddyfile, service wiring | `lint` ↔ `launch` |
| CDC pipelines, NATS/rpk transforms, multi-service behavior | `launch` ↔ `integrate` |
| Skaffold / K8s manifests / Kustomize overlays | `lint` ↔ `skaffold dev -p preview` (direct, not wrapped) |
| Playwright e2e specs | `verify` against a running `skaffold dev` |
| goreleaser config / image publishing | `release` (alone or ↔ `verify`) |

The agent is free to use direct commands when the verbs don't fit. But first consider whether the verb can be **customized** (via `.say.yaml`, `.vscode/tasks.json`, `compose.yaml`, etc.) to cover the case — a customized verb keeps the loop uniform across the repo.

## The Cascade-Advance Algorithm

```
1. Pick the layer where the current problem reproduces fastest.
2. Pick the verb pair for that layer.
3. Ping-pong between those two verbs until they're green.
4. Advance one layer: run the next slower layer's verbs.
   - Green? Advance again, or stop if you're at the end.
   - Red? Drop to the fastest layer that reproduces the new failure, fix there, advance.
5. Stop when the cascade is clean at every layer you care about for the current change.
```

This is neither "run every verb in order" nor "ignore the cascade entirely." It's "converge at your current layer, then test the next one."

## Diagnosing Down

When a slow layer fails, ask: "what's the fastest layer that reproduces this failure?" If a faster layer reproduces it, fix it there — the loop is ten or a hundred times tighter.

### Example — Docker build fails with TypeScript errors

**Wrong** (10+ min loop): edit → `docker build` → wait → TS error → edit → `docker build` …

**Right** (seconds loop):
```
sayt lint   → fix → sayt lint   → green
sayt launch → (passes now)
```

### Example — Integration test fails with wrong API response

**Wrong**: edit → `sayt integrate` → fail → edit → `sayt integrate` …

**Right**: reproduce as a unit test, fix at `test` (seconds), then re-run `integrate` to confirm it advances.

### Example — Playwright e2e fails with missing data

**Wrong**: edit migration → `skaffold run` → deploy → playwright → fail → edit …

**Right**: check the migration at the `lint` layer; reproduce in `launch` (compose) if needed; only come back to the e2e/skaffold layer once the data problem is fixed at a cheaper layer.

### When the bug is layer-specific

Some failures genuinely only reproduce at the slow layer — wrong base image, missing COPY, service startup order, K8s RBAC, image pull from the registry, etc. When diagnosing down doesn't find a faster reproducer, stay at that layer and iterate there.

## What Each Verb Does

### `setup` — install tools (mise), nothing more

`sayt setup` runs `mise install`. It installs the toolchain. It does **not** run `pnpm install`, `bundle install`, `pip install`, `go mod download`, or any project dependency manager. Warming project dependencies belongs in:

- The Dockerfile (for container builds)
- A `Taskfile.yml` `deps:` entry (for explicit local orchestration)

Run `setup` when `.mise.toml` changes or on a clean checkout. Run `doctor` to see which environment tiers are ready.

### `generate` / `lint` — static checks + generated code

`generate` creates source from templates/schemas (CUE, gomplate, protobuf, sqlc, buf, etc.). It has **side effects** — it writes files. Do not run `generate` inside `test` — tests must stay hermetic.

`lint` is the broad static-check verb. Put everything here that catches errors in seconds without running the app or a container:

- **App linters** — `pnpm lint`, `tsc --noEmit`, `cargo clippy`, `ruff check`, `go vet`, `eslint`, etc.
- **Generated code verification** — `generate` output matches sources; CUE constraints satisfied
- **Config validation** — `docker compose config`, `rpk connect lint`, `caddy validate`, `kustomize build`, `kubeconform`, `buf lint`, etc.

The rule: if it can fail in seconds without starting a process, it belongs in `lint`.

### `build` / `test` — the app only

`build` compiles the app. `test` runs unit tests **for the app only** — no docker, no network, no database, no full-stack services. Integration and end-to-end concerns belong in `integrate` and `verify`.

Both delegate to `.vscode/tasks.json` labels so the IDE and terminal share one source of truth.

### `launch` / `integrate` — full stack in containers

`launch` runs `docker compose run --build --service-ports launch` — your full dev stack with hot reload. `integrate` runs `docker compose up integrate --abort-on-container-failure` — the same stack plus an integration test runner.

`build`/`test` is the app layer. `launch`/`integrate` is the full stack. They answer different questions.

### `release` / `verify` — make the work public

`release` means *make the work public*. What that means depends on the project:

- **Library** — publish a package (npm, crates.io, PyPI, Maven Central) via goreleaser
- **CLI tool** — cut a tagged release, publish binaries via goreleaser
- **Server** — publish versioned container images to the cloud registry; the typical pattern is goreleaser delegating to `skaffold build --push` so image naming, platforms, and tags match the deploy pipeline
- **Deploy-on-release** — for projects where "make it public" means a live deploy, `release` may invoke `skaffold run -p production` directly, or goreleaser may publish + then skaffold deploys as a post-hook

Examples from this monorepo: `services/tracker/.goreleaser.yaml` uses `publishers: skaffold build --tag={{.Version}}` to push images. `plugins/sayt/.goreleaser.yaml` uses goreleaser's native binary release flow. Check existing `.goreleaser.yaml` files in the repo when adding `release` to a new service — match the surrounding convention.

For continuous delivery of servers, skaffold is usually already configured for preview/staging/production profiles. `sayt release` is the **manual** entry point that matches the CD pipeline — it's not a different deploy path.

`verify` runs `skaffold verify` for post-deploy validation (playwright e2e, smoke tests, load tests) against an already-deployed environment.

### Deploys without a verb

For preview/staging/production deploys, `skaffold` is already a verb runner — use it directly:

```bash
skaffold dev -p preview        # Kind, watch mode
skaffold run -p staging        # GKE / Cloud Run
skaffold run -p production     # manually approved promotion
```

Not every deploy needs a sayt wrapper. The verbs exist for the common cases.

## Anti-Patterns

| Anti-pattern | Why it's wrong | Do this instead |
|---|---|---|
| Walking every verb in order on every change | You waste minutes on layers your change didn't touch | Pick the layer where the problem reproduces fastest |
| Waiting for `test` to be green before running `launch` when you're editing compose.yaml | The bug is at the stack layer, not the app layer | Jump straight to `lint` ↔ `launch` |
| Iterating on TypeScript inside `docker build` | 5+ min per iteration | `lint` ↔ `test` locally (seconds) |
| Running `generate` inside `test` | `generate` has side effects (writes files); tests must be hermetic | Run `generate` separately; keep `test` pure |
| Retrying the same verb hoping for a different result | Masks the real issue | Read the error, diagnose down, fix at the reproducing layer |
| Wrapping `skaffold run -p preview` in a sayt verb for one project | Not every deploy needs a wrapper | Use `skaffold` directly unless the wrapping adds value |
| Putting `pnpm install` / `bundle install` inside `sayt setup` | `setup` is for toolchain (mise), not project dependencies | Put dep installs in the Dockerfile or a Taskfile `deps:` entry |
| Calling `sayt vet`, `sayt publish`, `sayt preview`, `sayt stage`, `sayt setup-butler`, `sayt develop`, `sayt loadtest`, `sayt observe` | These verbs do not exist | Use the real verbs below, or run the direct command |

## The Real Verbs

The complete, definitive list:

```
setup    doctor
generate lint
build    test
launch   integrate
release  verify
```

Anything else does not exist. If a use case doesn't fit a real verb, either **customize** the verb (via `.say.yaml`, `.vscode/tasks.json`, `compose.yaml`, etc.) or run the direct command (`skaffold dev`, `docker compose logs`, `mise exec -- <tool>`, etc.).

## Quick Reference

```bash
# Fresh checkout
sayt setup && sayt doctor

# Inner loops — pick whichever pair fits your current edit; ping-pong until green
sayt lint && sayt test         # app source code
sayt generate && sayt lint     # generated code
sayt lint && sayt launch       # docker / compose / config
sayt launch && sayt integrate  # multi-service behavior
sayt release && sayt verify    # publish + post-deploy checks

# Outer loop — skaffold directly for deploys
skaffold dev -p preview
skaffold run -p staging
skaffold run -p production
```
