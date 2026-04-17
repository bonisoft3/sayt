---
name: sayt-k8s
description: >
  How to write .goreleaser.yaml + skaffold.yaml for sayt release / verify —
  the monorepo pattern where goreleaser delegates image publishing to
  skaffold build --push, plus direct skaffold usage for deploys.
  Use when wiring release pipelines or preview/staging/production deploys.
user-invocable: false
---

# release / verify — Publishing and Skaffold Deploys

`sayt release` makes the work public — typically goreleaser publishing versioned artifacts, with `skaffold build --push` as the mechanism for building and pushing container images. `sayt verify` is a no-op by default; wire it in `.say.yaml` to run `skaffold verify` (or any other post-release check) when the project needs it.

For **deploys** to preview / staging / production, use `skaffold dev` / `skaffold run` directly. sayt has no wrapper verb for deploys — skaffold is already a verb runner.

## `sayt release` — Making Work Public

"Release" means *make the work public*. What that means depends on the project:

- **Library** — publish a package (npm, crates.io, PyPI, Maven Central) via goreleaser.
- **CLI tool** — cut a tagged release with multi-platform binaries via goreleaser.
- **Server (container-based)** — publish versioned container images to the cloud registry. The typical pattern is goreleaser delegating to `skaffold build --push` so image naming, platforms, and tags match the deploy pipeline.
- **Deploy-on-release** — for projects where "make it public" means a live deploy, `release` may invoke `skaffold run -p production` directly, or goreleaser may publish images and a separate step promotes them.

`sayt release` runs `release.nu`, which:

1. Computes the next version via `git-cliff` (or accepts `--version <v>` to bypass).
2. Validates against the `VERSION` file if present — aborts if they disagree, so you fix and re-run `sayt lint`.
3. Creates the git tag.
4. Runs `goreleaser release` with the computed version exported as `GORELEASER_CURRENT_TAG`.

`--snapshot` builds only, no tag or push.

### `.goreleaser.yaml` — Container Service via Skaffold

Most services in this monorepo use this shape: goreleaser owns versioning and changelog; skaffold owns image building and pushing.

```yaml
version: 2
project_name: services-tracker

before:
  hooks:
    - skaffold build -p production --push=false --tag={{ .Version }}

builds:
  - builder: zig
    skip: true

publishers:
  - name: skaffold
    cmd: skaffold build -p production --tag={{ .Version }}

release:
  disable: true
```

Why the stubbed `builds:` — goreleaser's native builders can't drive docker buildx for multi-arch images the way skaffold already does. The real work happens in `publishers:`. The GitHub release is disabled because the artifact is the image, not a tarball.

### `.goreleaser.yaml` — Binary Release

CLI tools (sayt itself, etc.) use goreleaser's native multi-platform build flow with `builds:`, `archives:`, and GitHub release enabled. No skaffold involvement.

When adding `release` to a new service, **look at a neighboring `.goreleaser.yaml` first** — match the surrounding convention.

## `sayt verify` — Post-Deploy Validation

Runs `skaffold verify` in the current directory. Skaffold executes verification containers defined in the `verify:` section of `skaffold.yaml` — e2e, smoke, load tests against an already-deployed environment.

## Deploys Use Skaffold Directly

```bash
# Preview — local Kind cluster
kind create cluster -n iris          # one-time
skaffold dev -p preview              # watch mode
skaffold run -p preview              # one-shot

# Staging — shared cloud deployment, followed by CI/CD
skaffold run -p staging

# Production — manually approved promotion from staging
skaffold run -p production
```

Kind clusters are ephemeral — `kind delete cluster -n iris && kind create cluster -n iris` anytime.

**Preview** is isolated with mocked externals, no outbound internet except vendored resources, production-like builds.
**Staging** is built hermetically by CI/CD, pushed to GCP by Skaffold (typically Cloud Build + Cloud Run), follows main branch.
**Production** is the same image as staging with different config; Crossplane manages infrastructure (Cloud Run, Cloud SQL, IAM, buckets).

## `skaffold.yaml` Shape

```yaml
apiVersion: skaffold/v4beta11
kind: Config
metadata:
  name: my-service

build:
  artifacts:
    - image: my-service
      docker: { dockerfile: Dockerfile }

profiles:
  - name: preview
    build:
      local: { push: false }           # Kind doesn't need a registry push
    deploy:
      kubectl:
        manifests: [k8s/preview/*.yaml]

  - name: staging
    build:
      googleCloudBuild: { projectId: my-project }
    deploy:
      cloudrun:
        projectid: my-project
        region: us-central1

  - name: production
    deploy:
      cloudrun:
        projectid: my-project-prod
        region: us-central1
```

### Example `verify` Task

The `verify:` section in `skaffold.yaml` runs arbitrary containers. For a playwright e2e suite wired through `.vscode/tasks.json`:

```json
{
  "label": "verify",
  "type": "shell",
  "command": "playwright",
  "args": ["test", "--config", "e2e/playwright.config.ts"],
  "group": { "kind": "test" },
  "problemMatcher": []
}
```

## Writing Good Skaffold Configs

1. **Profiles for preview, staging, production** as a minimum.
2. **Preview builds locally** with `push: false` — Kind doesn't need a registry.
3. **Staging and production use cloud build** (GCB or similar) for hermetic builds.
4. **Production is a promotion of staging** — same image, different config.
5. **Separate manifest dirs per env** — `k8s/preview/`, `k8s/staging/`, `k8s/production/`.

## Current flags

Run `sayt help release` and `sayt help verify` for current flags.
