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

sayt verbs are **independent tools for different layers**. No verb gates any other: `launch` doesn't require `test` green, `integrate` doesn't require `lint` green. The loop is a two-phase rhythm, not a pipeline:

1. **Ping-pong inside a layer.** Pick the verb pair that reproduces the current problem fastest and iterate between them until the layer is green.
2. **Advance the cascade.** Run the next slower layer to surface what only reproduces there. If it fails, drop back to wherever the failure reproduces fastest, fix, advance again.

You stop when failures stop appearing at the slower layers you care about — and, for a reported bug, no earlier than the layer and mode it was reported in.

## The Layers

| Layer | Verb pair | Feedback time | What it exercises |
|---|---|---|---|
| **Toolchain** | `setup` / `doctor` | seconds | `mise install` + environment-tier check |
| **Static** | `generate` / `lint` | seconds | Code generation, type-check, app linters, config validation |
| **App** | `build` / `test` | seconds | Compile + unit tests for the app only (no docker, no network) |
| **Stack** | `launch` / `integrate` | minutes | Full stack in `docker compose` |
| **Public** | `release` / `verify` | minutes to 10+ | Publish artifacts + post-deploy checks |

What each verb runs, and its config file, is in [reference.md](../sayt/reference.md). Two rules keep the layers honest: [what `setup` does not do](../cli/SKILL.md#what-setup-does-and-does-not-do), and `generate` writes files, so it never runs inside `test` — tests stay hermetic.

## Picking the Verb Pair

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

`lint` is the broad static-check verb: app linters (`tsc --noEmit`, `cargo clippy`, `ruff`, `go vet`), generated-code verification, config validation (`docker compose config`, `caddy validate`, `kubeconform`, `buf lint`). If it can fail in seconds without starting a process, it belongs in `lint`.

## The Cascade-Advance Algorithm

```
1. Pick the layer where the current problem reproduces fastest.
2. Ping-pong between that layer's two verbs until green.
3. Advance one layer: run the next slower layer's verbs.
   - Green? Advance again, or stop if you're at the end.
   - Red? Drop to the fastest layer that reproduces the new failure, fix there, advance.
4. Stop when the cascade is clean at every layer the change can reach.
   Fixing a report: stop no earlier than the reported layer, in the reported mode.
```

## Anchoring on the Report

A bug has two anchors: the **report layer** (where the reporter saw it) and the **report mode** — *automated* (a specific assertion failed) or *manual* (someone observed the behavior). Verification closes at that layer, in that mode:

- **Automated** — the exact test cited now passes. Not a similar one, not a faster unit test that covers "roughly the same thing".
- **Manual** — you reproduce the reporter's exact steps and confirm the fix. A green test at a faster layer shrinks iteration time; it does not close the loop.

Coverage in the *other* mode is a strengthening move, not part of closing: automate a manual report when regression risk outweighs test complexity; sanity-check an automated find by hand when that is cheap.

*"Card text wraps on flip"* — manual, in the browser: iterate at static (visual lint on a Storybook story) or app (a unit test on the font-size helper); close by flipping the card in the running app. *"`tests/cdc-text-gen.test.ts` fails after YAML change"* — automated, at app: edit the YAML, re-run that file; the passing test is the closure.

## Diagnosing Down

When a slow layer fails, ask which is the fastest layer that reproduces it, and fix there — the loop is ten or a hundred times tighter. A docker build failing on TypeScript errors is `sayt lint` → fix → green, then `sayt launch` passes; an integration test returning the wrong response is a unit test at `test`, then `integrate` to advance; an e2e missing data is the migration checked at `lint`, then `launch`. Some failures only exist at the slow layer — wrong base image, missing `COPY`, startup order, RBAC, a registry pull — and when no faster reproducer exists, you stay there.

## Platforms

Every verb has a **platform**, a string naming where it generates its effects; the defaults and how one is selected are in [sayt-lifecycle](../sayt/SKILL.md#configuring-sayt). Rulemap entries carry `platform:`; with `stop: true` a matching entry short-circuits the verb for that platform, so one verb does different work per target without multiplying names. Snapcards tiers its visual checks this way:

```yaml
say:
  integrate:
    rulemap:
      browser:            # DOM visual-lint against Storybook: fast, deterministic
        platform: browser
        priority: -1
        stop: true
        cmds: [{ do: "mise exec -- bun x playwright test tests/visual-lint.pw.ts" }]
  verify:                 # AI vision review of the running compose stack
    do: "with-env { SKIP_STORYBOOK: '1' } { mise exec -- bun x playwright test tests/vision-review-stack.pw.ts }"
    rulemap:
      docker:             # the same review against the docker-built Storybook
        platform: docker
        priority: -1
        stop: true
        cmds: [{ do: "mise exec -- bun x playwright test tests/vision-review-storybook.pw.ts" }]
```

`integrate@browser` is seconds per story and deterministic; `verify@docker` is seconds per story and costs credits; `verify` needs the stack up and takes minutes. Tightening a layout stays at the first; a story context string iterates at the second; a regression that only shows with real data goes to the third.

Add a platform when the *same question* must be answered against a *different artifact* — a verb you'd name `verify-storybook` or `integrate-browser-dom` is a platform. Do not add one to carry a flag: `--no-cache`, `--snapshot`, `--watch` are args on the existing verb.

## Anti-Patterns

| Anti-pattern | Do this instead |
|---|---|
| Walking every verb in order on every change | Pick the layer where the problem reproduces fastest |
| Waiting for `test` green before `launch` when editing compose.yaml | Jump to `lint` ↔ `launch` |
| Iterating on TypeScript inside `docker build` | `lint` ↔ `test` locally |
| Retrying the same verb hoping for a different result | Read the error, diagnose down, fix where it reproduces |
| Claiming fixed at your fastest layer while the report lives slower | Climb to the report layer, in the report mode |
| Wrapping `skaffold run -p preview` in a verb for one project | Use `skaffold` directly unless the wrapper adds value |

## Quick Reference

```bash
sayt setup && sayt doctor      # fresh checkout

sayt lint && sayt test         # app source code
sayt generate && sayt lint     # generated code
sayt lint && sayt launch       # docker / compose / config
sayt launch && sayt integrate  # multi-service behavior
sayt release && sayt verify    # publish + post-deploy checks

skaffold dev -p preview        # deploys: skaffold directly, no verb
skaffold run -p staging
skaffold run -p production
```
