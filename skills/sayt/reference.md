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
| `launch` | docker compose | `compose.yaml` + `Dockerfile` | `docker compose run --build --service-ports launch` |
| `integrate` | docker compose | `compose.yaml` + `Dockerfile` | `docker compose up integrate --abort-on-container-failure --exit-code-from integrate` |
| `release` | goreleaser (often delegating to `skaffold build --push`) | `.goreleaser.yaml` | `goreleaser release` with version computed from git-cliff |
| `verify` | skaffold | `skaffold.yaml` | `skaffold verify` |

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

**`verify`** — No `skaffold.yaml` or no `verify:` section → create one.

## The Real Verbs

```
setup    doctor
generate lint
build    test
launch   integrate
release  verify
```

Anything else does not exist. See `sayt-lifecycle` for the list of non-verbs and their replacements.
