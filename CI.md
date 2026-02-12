# Sayt CI (Normal Mode)

This document captures the **normal-mode** CI flow we have working today, plus what we intentionally deferred.

## Normal mode (composite action)

The composite action in `plugins/sayt/.github/actions/sayt-integrate` does:

1. `docker compose config --format json integrate` to produce a filtered compose file, then `jq` injects image names for any service without an explicit `image` field.
2. `docker/bake-action` with GHA cache (mode configurable) and `CI_IMAGE_PREFIX` tagging.
3. Hash the bake metadata digests and use `actions/cache` to gate the run.
4. If the digest cache misses, install `sayt` via the `saytw` action (local `./saytw` or latest), then run `./saytw integrate --target <target>`.

Important details:

- The digest gate always uses the `integrate` compose target (even if the action runs a different target).
- The action computes an image prefix from repo + target dir and injects image names for services that omit `image` in compose.
- The action assumes only basic shell features; jq is installed via action.
- The `saytw` composite action installs `sayt` and warms its cache, optionally seeding `~/.cache/sayt` from a `seed-dir` (used when you need local `*.nu`/`*.toml` files for `--target` support). The `sayt-integrate` action exposes this via its own `seed-dir` input.

## Deferred / advanced mode

Advanced mode (moving integration work into a Dockerfile build with dind and GHA cache inside the container) was too complex and is deferred.

What we *did* keep for later:

- `dind.nu` now exports `ACTIONS_CACHE_URL` and `ACTIONS_RUNTIME_TOKEN` (when present) in `env-file`, so future dind-based builds can use GHA cache without extra wiring.

## Known simplifications (to revisit later)

- No PR/fork awareness. Fork PRs will still attempt to push to GHCR and can fail.
- No per-branch or per-PR cache scopes. Cache scope is fixed to `main`.
- No cache-from layering (e.g., main + PR). Only a single cache scope is used.
- No conditional push. The bake step always pushes.
- No custom dependency-closure logic. Target list comes from `docker compose config integrate` without additional filtering.
- No special error handling for missing digests.

The goal is a minimal, understandable action; later we can reintroduce richer behavior along with cache scoping.
