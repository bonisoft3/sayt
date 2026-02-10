# Sayt CI

This document captures the **normal** and **advanced** CI flows we have working today.

## Normal mode (composite action)

The composite action in `plugins/sayt/.github/actions/sayt/integrate` does:

1. `docker compose config --format json integrate` to produce a filtered compose file, then `jq` injects image names for any service without an explicit `image` field.
2. `docker/bake-action` with GHA cache (mode configurable) and `CI_IMAGE_PREFIX` tagging.
3. Hash the bake metadata digests and use `actions/cache` to gate the run.
4. If the digest cache misses, install `sayt` via the `saytw` action (local `./saytw` or latest), then run `./saytw integrate --target <target>`.

Important details:

- The digest gate always uses the `integrate` compose target (even if the action runs a different target).
- The action computes an image prefix from repo + target dir and injects image names for services that omit `image` in compose.
- The action assumes only basic shell features; jq is installed via action.
- The `sayt/install` composite action installs `sayt` and warms its cache, optionally seeding `~/.cache/sayt` from a `seed-dir` (used when you need local `*.nu`/`*.toml` files for `--target` support). The `sayt/integrate` action exposes this via its own `seed-dir` input.

## Advanced mode (cached compose up)

Advanced mode moves the **compose up** work into a Dockerfile `RUN`, so the entire integration run is cached by BuildKit. This is implemented via a `ci` target in `plugins/sayt/Dockerfile` that runs:

- `dind.sh ./saytw integrate --target integrate`

Key pieces:

- `plugins/sayt/docker-bake.override.hcl` defines the `ci` target, secrets, and cache wiring.
- `sayt integrate --target ci --bake --allow fs.read=<repo-root>` uses the bake file for local runs (CI passes `--allow fs.read=${{ github.workspace }}` via the composite action).
- The composite action generates `host.env` (via `./sayt dind-env-file --socat`) and **appends** `CACHE_FROM` / `CACHE_TO`.
- The `ci` build uses `RUN --mount=type=secret,id=host.env` so `dind.sh` can export all the envs (including cache settings).
- `dind-vrun` reuses `/run/secrets/host.env` when present, allowing recursive runs to keep the same host env.

Cache policy (advanced mode):

- **main branch:** `cache-from=main`, `cache-to=main` (mode `max`)
- **same-repo PRs:** `cache-from=main + pr`, `cache-to=pr` (mode `max`)
- **fork PRs:** `cache-from=main`, **no cache-to**, **no GHCR push**
- **non-main branches:** `cache-from=main + branch`, `cache-to=branch` (mode `max`)

What we *did* keep for later:

- `dind.nu` exports `ACTIONS_CACHE_URL` and `ACTIONS_RUNTIME_TOKEN` (when present) in `env-file`, so dind-based builds can use GHA cache without extra wiring.

## Known simplifications (to revisit later)

- No additional cache scopes beyond main/branch/pr.
- No custom dependency-closure logic. Target list comes from `docker compose config integrate` without additional filtering.
- No special error handling for missing digests (normal mode).

The goal is a minimal, understandable action; later we can reintroduce richer behavior along with cache scoping.
