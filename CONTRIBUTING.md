---
type: howto
title: Contributing to sayt
description: The file map of plugins/sayt, how to run its tests, and the loop for changing it.
---

# Contributing to sayt

Sayt is nushell driven by a CUE schema, launched by a small zig binary that fetches a pinned mise and runs everything through mise tool stubs. Every path is relative to this directory, so the same tree is a monorepo plugin, the copybara mirror `bonisoft3/sayt`, and a release archive.

## File map

**Entry and dispatch**
- `sayt.nu` — the CLI: `--directory`, `--platform` / `verb@platform`, `--verb`, `--script`, `--install` / `--global`, `--commit`. Mirrors CLI flags into `SAY_<VERB>_ARGS_*`, then runs the override chain: `.sayt.<verb>.nu`, `.sayt.nu` with `main <verb>`, config rules. A `say.self.version` pin re-execs through the colocated `saytw`.
- `config.cue` (`package say`) — schema and defaults: `#MapAsList` / `#MapToList` (the ordered-map rule pattern), `#verb`, the built-in rulemaps, the default `self.version`.
- `config.nu` — `load-config`: `cue export` of `.say.{cue,yaml,yml,json,toml,nu}` unified with `config.cue`.
- `rulemap.nu` — runs a verb's rules: platform filter, verb- and rule-level args, `keep_going`, generate's output selectors; `resolve-engine` gives `sayt help <verb>` the engine module's own flag help.

**Verb engines** — one module per built-in, wired in `config.cue`: `setup.nu`, `doctor.nu`, `build.nu` and `test.nu` (through `vscode.nu`, the tasks.json runner), `launch.nu`, `integrate.nu` (with `compose.nu` and `dind.nu`, the daemon bridge), `release.nu` (with `semver.nu`: monorepo-prefixed tags computed by git-cliff), `verify.nu` (a nop). Generate and lint built-ins: `generate-gomplate.nu`, `generate-cue.nu`, `auto-bayt.nu`, `auto-cue.nu`.

**Tools** — `tools.nu` wraps each external tool in a `run-*` that goes through a mise tool stub: `cue.toml`, `docker.toml`, `compose.toml`, `uvx.toml`, `nu.toml` / `nu.musl.toml`, `goreleaser.toml`, `git-cliff.toml`, `task.toml`. Pins live in the stubs and, for sayt's own build (zig, 7zip, task), in `.mise.toml` + `mise.lock`.

**The loop** — `loop.cue`, the `sayt:loop` package: from an app's build and test commands and its declared checks, `#Loop` emits the `.say.yaml` and `.vscode/tasks.json` the verbs read, and that `.say.yaml` is validated against `config.cue`. Pronto rosters it as `loops/sayt.cue`, so a program imports it as `pronto/loops:sayt`.

**Launchers**
- `sayt.zig` + `build.zig` + `ca-certificates.crt` — the released binary: finds or downloads mise into the cache dir, then runs `sayt.nu` through the nu stub; local mode when `sayt.nu` sits beside the binary or in its parent.
- `sayt.sh` — the same for a checkout, in POSIX sh; what `cd.yml` and the `Dockerfile`'s `ci` target run.
- `saytw`, `saytw.ps1` — the repository wrappers: download the released `SAYT_VERSION` (default: this `VERSION`) into the cache and exec it.
- `install` — the polyglot sh/PowerShell one-liner behind the install URL; it runs `saytw --install`.

**Own lifecycle** — `.say.cue` (lint: the version pin shared by `VERSION`, `saytw`, `saytw.ps1`, `compose.yaml`, `config.cue` and the plugin manifests, plus the buildkit digest shared by the integrate action and `cd.yml`); `.vscode/tasks.json` (build: `zig build`; test: `zig build test`, then every `*_test.nu`); `compose.yaml` + `Dockerfile` (the integrate graph, below); `.sayt.verify.nu` (verify: install the published wrapper into a temp `HOME`, smoke-test the binary, check that a `v0.2.0` pin downgrades); `.goreleaser.yaml` (zig builder, seven targets, ghcr images); `cliff.toml`; `.github/workflows/cd.yml` (on a tag: publish the CUE module, then `./sayt.sh release --changelog --clean`; on main, the same with `--snapshot`).

**Distribution** — `.mirror/cue.mod/module.cue`, staged by copybara as the mirror's `cue.mod/module.cue`; `.github/actions/sayt/*`, the composite actions; `.claude-plugin/`, `skills/`, `agents/`, the Claude Code plugin; `docs/`, the index, decisions and archive.

## Running the tests

From `plugins/sayt`, with nothing installed but a shell and docker:

```sh
./sayt.sh lint        # the shared version pins
./sayt.sh test        # zig build test, then *_test.nu in parallel
./sayt.sh integrate   # the compose graph in compose.yaml
```

`*_test.nu` are plain nushell scripts with `use std/assert`; run one alone with `nu <name>_test.nu`. `ci_test.nu`, `depot_test.nu` and `integrate_action_test.nu` drive the composite actions' bash steps and skip on Windows. `sayt integrate` builds the release assets into a caddy `release-server`, runs `saytw` against it from alpine, wolfi and ubuntu (root and non-root), curl and PowerShell images, and runs `integrate_it.nu` — the docker-backed integrate tests — in the `integrate-it` service; `--target test` or `--target test-docker-image` builds the Dockerfile target of that name. A failed run leaves the containers up for `docker compose logs`.

## The loop for a change

Pick the pair that reproduces the problem fastest ([skills/tdd/SKILL.md](skills/tdd/SKILL.md)): dispatch or config, `lint` ↔ `test`; a launcher or wrapper, `integrate`; a composite action, its `*_test.nu`, then a workflow run. A behavior change to a verb comes with a regression test in the matching `*_test.nu`, saying what broke and why.

Bumping the version touches every file the `.say.cue` shared pin names, and `./sayt.sh lint` fails until they agree; the rest of a release is the README's [Releasing](README.md#releasing).
