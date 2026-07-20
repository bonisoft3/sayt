# sayt Quick Reference

Compact verb → tool → config mapping. For configuration details see the per-verb skills: `sayt-cli`, `sayt-code`, `sayt-ide`, `sayt-cnt`, `sayt-k8s`.

## Verb → Tool → Config

| Verb | Tool | Config | What it runs |
|---|---|---|---|
| `setup` | mise | `.mise.toml` + `mise.lock` | `mise trust -y -a -q && mise install` |
| `doctor` | mise, cue, docker, kind, skaffold, gcloud, crossplane | — | checks each tool's availability per tier |
| `generate` | CUE + gomplate + nushell | `.say.{cue,yaml,nu}` | runs `say.generate.rulemap` entries; built-ins `auto-gomplate` + `auto-cue` |
| `lint` | CUE + nushell | `.say.{cue,yaml,nu}` | runs `say.lint.rulemap`; built-in `auto-cue` does `copy` / `shared` / `vet` checks |
| `build` | CUE | `.vscode/tasks.json` | runs the task labeled `"build"` |
| `test` | CUE | `.vscode/tasks.json` | runs the task labeled `"test"` |
| `launch` | docker compose | `compose.yaml` + `Dockerfile` | `docker compose down -v`, then `docker compose up launch --build --force-recreate --remove-orphans --wait` (`--watch` for foreground HMR) |
| `integrate` | docker compose (or buildx bake) | `compose.yaml` + `Dockerfile` | `docker compose down -v`, then `docker compose up integrate --build --force-recreate --abort-on-container-failure --exit-code-from integrate --renew-anon-volumes --remove-orphans --attach-dependencies`; build axis selectable with `--bake` / `--depot` / `--no-build` |
| `release` | goreleaser (often delegating to `skaffold build --push`) | `.goreleaser.yaml` | `goreleaser release` with version computed from git-cliff |
| `verify` | — (nop by default) | `.say.yaml` | nothing by default; customize in `.say.yaml` (e.g. `skaffold verify`) |

### `integrate` build axes and capability flags

The build axis is single-valued (flags conflict): `--bake` (build via `docker buildx bake`), `--depot` (same outer bake, inner runs `depot bake`; needs `DEPOT_PROJECT_ID`), `--no-build` (skip build, images must pre-exist). `--no-up` stops after the build — `--bake --no-up` is the *envelope*: the test runs inside the bake `RUN` and bake's exit code is the verdict. Multiple `--target` values require a bake build.

Capability flags collect host abilities into the run: `--dind` (runtime `compose up` gets a daemon), `--dind-bridge` (a build `RUN` gets a daemon), `--with-buildx` (inject the host buildx builder; implies `--dind-bridge`), `--with-kube`, `--with-testcontainers`, `--with-host-env`, `--builder <name>`. Cache escape hatches: `--no-cache`, `--no-cache-from`, `--no-cache-to`.

For **deploys** (preview/staging/production), use `skaffold` directly — there is no sayt wrapper:
```
skaffold dev -p preview
skaffold run -p staging
skaffold run -p production
```

## Bootstrapping a New Project

1. `.mise.toml` — pin tool versions; run `mise lock` and audit platform coverage.
2. `sayt setup && sayt doctor` — install and verify the toolchain.
3. `.vscode/tasks.json` — define `build` and `test` labels for the language.
4. `sayt lint && sayt test` — verify the app-layer loop.
5. `Dockerfile` (multi-stage with `debug` + `integrate`) + `compose.yaml` (with `launch` + `integrate` services) — containerize.
6. `sayt launch && sayt integrate` — verify the stack-layer loop.
7. Optional: `.goreleaser.yaml` for `sayt release`; `skaffold.yaml` for `sayt verify` and direct deploys.

## Troubleshooting by Verb

**`setup`** — `mise` missing? Install via `curl https://mise.jdx.dev/install.sh | sh`. Tool not in registry? Use `"github:owner/repo"` format. Trust error? Check `.mise.toml` is valid TOML.

**`doctor`** — A ✗ on any tier means a missing tool for that tier. See the table in `sayt-cli`.

**`build` / `test`** — Task label not found means `.vscode/tasks.json` is missing a `"build"` or `"test"` entry. The underlying compiler/test runner's errors come through verbatim; fix the source.

**`generate` / `lint`** — No output means no `.say.*` config or built-ins were set to null. Check whether `auto-gomplate` / `auto-cue` were disabled.

**`launch` / `integrate`** — Docker daemon not running is the most common cause. After a failed `integrate`, containers are left running: `docker compose logs && docker compose down -v`.

**`release`** — No `.goreleaser.yaml` → create one. No git tag and not snapshotting → tag first or use `sayt release --snapshot`. VERSION file disagrees with the computed tag → fix the file, run `sayt lint`, retry.

**`verify`** — Nop by default; if you customized it in `.say.yaml` (e.g. `skaffold verify`), the underlying tool's errors come through verbatim.

## The Real Verbs

```
setup    doctor
generate lint
build    test
launch   integrate
release  verify
```

Anything else does not exist. See `sayt-lifecycle` for the list of non-verbs and their replacements.
