---
name: sayt-cli
description: >
  How to write .mise.toml + mise.lock for sayt setup / doctor — tool
  versions, the http: backend, lockfile auditing across platforms,
  and mise exec for non-shim invocations.
  Use when setting up project toolchains or fixing missing tools.
user-invocable: false
---

# setup / doctor — Tool Management with mise

`sayt setup` installs the project toolchain: `mise trust -y -a -q && mise install`. A `.sayt.setup.nu`, or a `.sayt.nu` defining `main setup`, replaces that entirely (see below).

`sayt doctor` checks which environment tiers are ready:

| Tier | Tools checked |
|------|---|
| pkg  | mise (or scoop on Windows) |
| cli  | cue, gomplate |
| ide  | cue |
| cnt  | docker |
| k8s  | kind, skaffold |
| cld  | gcloud |
| xpl  | crossplane |

After the tier table, `doctor` also prints:

- **Release Checks** (contextual) — shows `goreleaser` if the current directory has `.goreleaser.yaml` or `.goreleaser.yml`. Skipped when no release config exists.
- **Health Checks** — DNS resolution for `google.com` and `github.com`. If either fails, `doctor` exits non-zero so the common "offline / flaky DNS / corp proxy blocking" case is caught before it turns into a mysterious `mise install` or `docker pull` failure downstream.

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

## `.mise.toml` Basics

```toml
[settings]
locked = true            # fail if mise.lock is out of sync
lockfile = true          # maintain mise.lock
experimental = true      # enable some plugin features
paranoid = false         # skip aggressive checksum verification

# Security features usually disabled during development for speed:
github.slsa = false
github.github_attestations = false
aqua.cosign = false
aqua.slsa = false
aqua.github_attestations = false
aqua.minisign = false

[tools]
node = "22.14.0"
go = "1.22"
"github:pnpm/pnpm" = "9.15.2"
"github:bufbuild/buf" = "1.32.1"
```

**Pin exact versions** (`"22.14.0"` not `"22"`) so the lockfile can match. Use registry names (`node`, `go`) where available; `github:` for tools not in the default registry.

## Per-Language Starter Tools

| Language | Typical tools |
|---|---|
| **Node / pnpm** | `node`, `"github:pnpm/pnpm"` |
| **Node / Bun** | `node` (Bun and Deno are picked up from `.tool-versions` if present) |
| **Go** | `go`, `"github:sqlc-dev/sqlc"`, `"github:gotestyourself/gotestsum"` |
| **JVM (Maven)** | `java`, `maven` |
| **JVM (Gradle)** | `java` (gradlew ships in the repo) |
| **Python** | `python`, `"pipx:uv"` |
| **Ruby** | `ruby` |
| **Elixir** | `erlang`, `elixir` (version must match OTP: `1.18.3-otp-27`) |
| **.NET** | `dotnet` |
| **Scala (sbt)** | `java`, `sbt` (sbt fetches Scala itself) |
| **Rust** | `"cargo:cargo-audit"` etc. — toolchain via rustup, not mise |
| **C / autotools** | none — system build tools |

### `locked = true` compatibility

`locked = true` only works for backends whose lockfile entries carry download URLs. Omit `locked = true` (but keep `lockfile = true`) for backends that don't:

| Backend | URLs in lockfile? | Supports `locked = true`? |
|---|---|---|
| `core:node`, `core:go`, `core:bun`, `core:deno`, `core:ruby` | Yes | Yes |
| `core:java`, `core:python`, `core:erlang`, `core:elixir` | No | No |
| `asdf:dotnet`, `asdf:sbt` | No | No |
| `aqua:` (maven, etc.) | Yes | Yes |
| `github:` | Usually | Usually |
| `http:` | Yes, one per platform (see below) | Yes |
| `cargo:` | No | No |
| `pipx:` | Varies | Varies |

When in doubt, set `lockfile = true`, leave `locked = true` off, and rely on exact version pins for reproducibility.

### `http:` entries are written by hand

`mise lock` records only the platform it runs on, whatever the backend and
whatever `--platform` says. An `http:` tool therefore gets one entry per run,
and every lockfile here that covers linux and windows was written by hand.

Write the checksum beside the URL: mise verifies it on install, and without one
the download is guarded by nothing. Compute it with blake3 over the exact
artifact the URL serves, and expect `mise lock` to leave the other platforms'
entries alone rather than refresh them.

### Platform stubs

sayt uses mise "tool stubs" for CUE, Docker, Compose, and uvx. These have platform-specific TOML configs: `cue.toml`, `docker.toml`, `compose.toml`, `uvx.toml`, `nu.toml`. sayt selects the right one automatically.

Compose gets its own stub rather than riding `docker compose`, which would resolve whatever plugin version the host installed.

sayt runs its own pinned mise and puts it first on the PATH of every process it starts, so `mise exec --` in a `do:` works with no global mise. Project operations honor the project's `locked` setting; `mise lock` and the tool stubs run unlocked, since they precede a usable lockfile.

## `mise lock` — Always Audit

`mise lock` produces `mise.lock`. **Always audit the output, and audit it again whenever `.mise.toml` changes.** A regression here ships broken builds on the platforms that don't get CI coverage.

### Minimum audit after every `mise lock`

1. **Platform coverage.** For each tool, verify the lockfile has entries for every platform you care about. Target `darwin-arm64`, `linux-x64`, `linux-arm64`, and `windows-x64` unless you know a platform doesn't apply. Core tools (`core:java`, `core:python`, etc.) will lack URLs — that's expected; it just means `locked = true` can't apply to them.
2. **Asset correctness.** For each platform entry, verify the URL points at the right binary. A `linux-arm64` entry pointing at an Android binary is a silent failure until an ARM Linux runner picks it up.
3. **No regressions.** Compare against the previous lockfile. If a tool lost platform coverage it had before, `mise lock` silently dropped it — fix it before committing.

### Known pitfalls

1. **GitHub API rate limiting.** When rate-limited, `mise lock` silently produces `github:` entries with no platform URLs. These fail with "No lockfile URL found" under `locked = true`. Fix: set `GITHUB_TOKEN` before running `mise lock`, or patch the lockfile using `gh api repos/OWNER/REPO/releases/tags/TAG --jq '.assets[] | {name, id}'`.
2. **Wrong Windows asset.** `mise lock` may pick non-Windows assets for `windows-x64` (e.g., `.rpm` for sops). Every `windows-x64` URL must end in `.exe` or `.zip`.
3. **Wrong Linux ARM64 asset.** `mise lock` may pick Android binaries (`aarch64-linux-android`) for `linux-arm64`. Verify `linux-arm64` URLs contain `unknown-linux-musl` or `unknown-linux-gnu`.
4. **Binary renaming on Windows (github: backend).** Some tools (e.g., yq) ship as `tool_windows_amd64.exe` inside zips. The `github:` backend doesn't rename extracted binaries. Fix: switch to `http:` with a bare binary URL.

## `http:` Backend

Use `http:` when a tool isn't on GitHub or when `github:` produces wrong binaries on Windows. Zero API calls, fully declarative.

```toml
[tools]
"github:bufbuild/buf" = "1.32.1"

[tools."http:skaffold"]
version = "2.17.2"
url = 'https://storage.googleapis.com/skaffold/releases/v{{ version }}/skaffold-{{ os(macos="darwin") }}-{{ arch(x64="amd64") }}'

[tools."http:skaffold".platforms]
windows-x64 = { url = 'https://storage.googleapis.com/skaffold/releases/v{{ version }}/skaffold-windows-amd64.exe' }

[tools."http:docker-cli"]
version = "28.5.1"
url = 'https://download.docker.com/{{ os(macos="mac") }}/static/stable/{{ arch(x64="x86_64", arm64="aarch64") }}/docker-{{ version }}.tgz'
bin_path = "docker/docker"

[tools."http:docker-cli".platforms]
windows-x64 = { url = 'https://download.docker.com/win/static/stable/x86_64/docker-{{ version }}.zip' }
```

Important rules:
- **Flat `[tools]` entries must come first**, then `http:` sub-tables.
- **`version` must not include a `v` prefix** if the URL template already adds it (`url = '.../v{{ version }}/...'` → `version = "4.44.2"`, not `"v4.44.2"`).
- **Windows overrides** are required when the Windows URL differs (e.g., `.exe` suffix, `.zip` archive).
- **`bin_path`** picks the binary inside an extracted archive when it's not the archive name.
- Templates use **Tera** syntax, not Go template syntax.

## `mise exec --` in Scripts, Compose, and CI

When you need to invoke a mise-managed tool from somewhere that isn't inside a mise shim — `Taskfile.yml`, `compose.yaml` `command:`, a CI step, a lint recipe, a `.say.yaml` `do:` block — prefix the call with `mise exec --`:

```yaml
# .say.yaml
say:
  lint:
    do: |
      mise exec -- pnpm lint
      mise exec -- rpk connect lint services/transform/pipelines/*.yaml
      mise exec -- caddy validate --config services/proxy/Caddyfile --adapter caddyfile
```

```yaml
# Taskfile.yml
tasks:
  check:
    cmds:
      - mise exec -- kubeconform -summary -strict k8s/base/*.yaml
```

This resolves the tool via mise regardless of whether the caller's shell has shims activated, and picks up the version pinned in `.mise.toml` rather than whatever's on `$PATH`. Prefer `mise exec --` over a bare tool name anywhere the invocation leaves an interactive shell.

## Custom Setup via `.sayt.nu`

For setup beyond what mise provides:

```nushell
# .sayt.nu
use tools.nu [run-mise]

export def "main setup" [] {
    run-mise install
    # then: fetch non-mise assets, seed local state, etc.
}
```

A `main setup` here replaces the built-in verb, so it calls `run-mise install` itself to keep the toolchain step; sayt puts its own directory on `NU_LIB_DIRS`, which is what resolves `use tools.nu`. Declaring extra commands beside the builtin in `say.setup.rulemap` instead requires re-declaring the builtin's `cmds`, since the builtin rule carries `stop: true`.

## Writing Good `.mise.toml` Files

1. **Pin exact versions.** `"22.14.0"` not `"22"`.
2. **Always generate and audit the lockfile.** `mise lock` + manual platform-coverage check, every time `.mise.toml` changes. Never ship a lockfile regression.
3. **Use `locked = true` only when the backend supports URLs.** See the compatibility table.
4. **Prefer backends in order: `core:` > `http:` > `github:` > `aqua:`.** `aqua:` hits the GitHub API on every install and fails under CI rate limits.
5. **Check `.tool-versions`.** If it exists, mise picks it up automatically — no need to duplicate.

## Current flags

Run `sayt help setup` and `sayt help doctor` for current flags.
