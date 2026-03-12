---
name: sayt-tdd
description: >
  The cascading TDD loop for sayt projects. Use when implementing features,
  fixing bugs, or diagnosing failures. Teaches how to find the tightest
  feedback loop by cascading down through isolation levels: local (build/test),
  container (launch/integrate), and k8s/cloud (release/verify).
user-invocable: false
---

# TDD Loop — Cascading Isolation Levels

When developing with sayt, always work at the **tightest possible feedback loop**. Never jump straight to the slowest environment. Cascade down through isolation levels until you find the fastest loop that reproduces your problem, fix it there, then cascade back up.

## The Three Isolation Levels

| Level | Verbs | Feedback time | When to use |
|-------|-------|---------------|-------------|
| **Local** (IDE) | `build`, `test` | seconds | Compilation errors, unit test failures, type errors |
| **Container** (cnt) | `launch`, `integrate` | minutes | Dockerfile issues, service integration, compose config |
| **K8s/Cloud** (k8s) | `release`, `verify` | 10+ minutes | Deployment, E2E acceptance, production readiness |

Each level has an **action verb** (manual/exploratory) and a **check verb** (automated validation):

| Action (manual) | Check (automated) | Level |
|-----------------|-------------------|-------|
| `generate` | `lint` | Code generation |
| `build` | `test` | Local compilation + unit tests |
| `launch` | `integrate` | Container dev + integration tests |
| `release` | `verify` | K8s deploy + E2E acceptance |

## The Cascade-Down Algorithm

When you hit a failure at any level:

```
1. STOP — Do not retry at the same level
2. CASCADE DOWN — Can this failure be reproduced at a faster level?
   - Docker build fails with TypeScript error? → Run type-check locally (seconds, not minutes)
   - Integration test fails with wrong API response? → Write a unit test for that endpoint
   - E2E test fails with missing data? → Check the migration script locally
3. FIX at the tightest level where the failure reproduces
4. CASCADE BACK UP — Re-run the check at the original level
```

### Example: Docker Build Fails with TypeScript Errors

**Wrong approach** (10+ min loop):
```
edit → docker build → wait 5 min → see TS error → edit → docker build → ...
```

**Right approach** (seconds loop):
```
edit → pnpm type-check → see TS error → fix → pnpm type-check → green
→ then docker build (should pass now)
```

### Example: Skaffold E2E Fails

**Wrong approach** (20+ min loop):
```
edit → skaffold run → kind load → deploy → playwright → fail → edit → ...
```

**Right approach**: cascade down:
```
1. Can I reproduce with docker compose? (minutes)
   → Yes: fix at container level, iterate with `just integrate`
   → No: continue down

2. Can I reproduce with a unit test? (seconds)
   → Yes: write the test, fix, iterate with `just test`
   → No: the issue is k8s-specific, fix skaffold/k8s config
```

## Working at Each Level

### Level 1: Local (build/test) — The Tight Inner Loop

This is where you spend 90% of your time.

```bash
# The core loop
sayt build          # Compile
sayt test           # Run unit tests
```

**Before going to containers, verify locally:**
- Type-check passes (for TypeScript: `pnpm type-check` or `pnpm exec tsc --noEmit`)
- Linting passes (`sayt lint`)
- Unit tests pass (`sayt test`)
- Build succeeds (`sayt build`)

**When the build fails:**
1. Read compiler output — is it a source error or a config error?
2. If source: fix the code, re-run `sayt build`
3. If config: fix `.vscode/tasks.json` or `.mise.toml`, re-run `sayt build`

**When tests fail:**
1. Read test output for assertion failures
2. Fix the code (not the test, unless the test expectation is wrong)
3. Re-run `sayt test` (which may re-compile)

### Level 2: Container (launch/integrate) — The Middle Loop

Only enter this loop after Level 1 is green.

```bash
sayt launch         # Start dev environment (docker compose up)
# Manually test in browser/API
sayt integrate      # Run integration tests in containers
```

**When integration fails:**
1. Is it a Dockerfile issue? → Fix Dockerfile, retry `sayt integrate`
2. Is it a compose config issue? → Fix compose.yaml, retry
3. Is it a code issue only visible in containers? → Try to reproduce at Level 1 first
4. Is it a service dependency issue? → Check compose service health, logs

**Common container-only failures:**
- Missing COPY in Dockerfile (file exists locally but not in image)
- Wrong base image (tools missing in container)
- Service startup order (depends_on doesn't wait for healthy)
- Environment variables not set in compose

### Level 3: K8s/Cloud (release/verify) — The Outer Loop

Only enter this loop after Level 2 is green.

```bash
sayt release        # Deploy to K8s (skaffold run) or release artifacts
sayt verify         # Run E2E/acceptance tests against deployment
```

**When deployment fails:**
1. Is it a build issue? → Should have been caught at Level 2
2. Is it a K8s config issue? → Fix skaffold.yaml or K8s manifests
3. Is it a resource issue? → Check Kind cluster capacity, image loading

**When E2E fails:**
1. Is the service actually running? → `kubectl get pods`, check logs
2. Is it a code issue? → Try to reproduce at Level 1 or 2
3. Is it a test environment issue? → Check mocks, test data, network policies

## Setup Dependencies

sayt verbs are intentionally independent — `build` does not automatically run `setup`. This is by design for speed (don't re-install tools every build). But when starting fresh:

```bash
sayt setup          # Install tools (run once or after .mise.toml changes)
sayt doctor         # Verify everything is installed
```

If `build` fails with "command not found", the fix is `sayt setup`, not re-running build.

For projects needing dependency orchestration, use `sayt --task build` which delegates to a Taskfile.yaml with explicit `deps:` declarations.

## The Generate/Lint Pair

Code generation sits between setup and build:

```bash
sayt generate       # Generate code from templates/schemas
sayt lint           # Validate generated code matches sources
```

Run `generate` when:
- Proto files changed → regenerate JSON schemas
- CUE templates changed → regenerate config files
- Template data changed → regenerate output files

Run `lint` to verify:
- Generated files are up-to-date
- CUE constraints are satisfied
- Template outputs match their inputs

## Anti-Patterns

| Anti-pattern | Why it's wrong | Do this instead |
|-------------|---------------|-----------------|
| Jump to `integrate` without `build`+`test` passing | Waste minutes on issues catchable in seconds | Always green at Level 1 before Level 2 |
| Retry same command hoping for different result | Masks the real issue | Diagnose, cascade down, fix |
| Fix TypeScript errors inside Docker | 5+ min per iteration | Run type-check locally (seconds) |
| Run E2E to test a logic change | 20+ min per iteration | Write a unit test |
| Skip `setup` after changing `.mise.toml` | Build fails with missing tools | Run `setup` when toolchain config changes |
| Edit Dockerfile to fix code bugs | Wrong layer | Fix code at Level 1, rebuild image |

## Decision Tree: Where Should I Fix This?

```
Failure → Can I write a unit test?
  → Yes: Fix at Level 1 (build/test)
  → No: Is it a container config issue?
    → Yes: Fix Dockerfile/compose, re-run integrate
    → No: Is it a service integration issue?
      → Yes: Fix at Level 2 with compose
      → No: Fix at Level 3 (k8s config/manifests)
```

## Quick Reference

```bash
# Fresh start
sayt setup && sayt doctor

# Inner loop (seconds)
sayt generate && sayt lint && sayt build && sayt test

# Middle loop (minutes) — only after inner loop is green
sayt integrate

# Outer loop (10+ min) — only after middle loop is green
sayt release && sayt verify

# With dependencies via Taskfile
sayt --task build    # Runs setup → generate → build via Taskfile.yaml
```
