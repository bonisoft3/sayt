---
name: sayt-cli
description: >
  How to write .mise.toml files with correct tool versions, settings, and platform stubs.
  Use when setting up project toolchains, fixing missing tools, or configuring sayt setup/doctor.
user-invocable: false
---

# setup / doctor — Tool Management with mise

`sayt setup` installs project toolchains. `sayt doctor` verifies each environment tier is ready.

## How It Works

1. `sayt setup` looks for `.mise.toml` in the current directory
2. Runs `mise trust -y -a -q` to trust the config
3. Runs `mise install` to install all specified tools
4. If `.sayt.nu` exists, recursively calls it with `setup` for custom logic

`sayt doctor` checks which environment tiers have their required tools available:

| Tier | Tools checked |
|------|--------------|
| pkg | mise (or scoop on Windows) |
| cli | cue, gomplate |
| ide | cue |
| cnt | docker |
| k8s | kind, skaffold |
| cld | gcloud |
| xpl | crossplane |

## `.mise.toml` File Format

mise uses TOML configuration to specify tool versions per project.

### Structure

```toml
[settings]
locked = true           # Use lockfile for reproducible installs
lockfile = true         # Generate/use mise.lock
experimental = true     # Enable experimental features
paranoid = false        # Disable paranoid mode

[tools]
# Standard registry tools
node = "22.14.0"
go = "1.22"
java = "openjdk-21.0"
python = "3.12"

# GitHub-hosted tools (not in default registry)
"github:pnpm/pnpm" = "9.15.2"
"github:sqlc-dev/sqlc" = "1.28.0"
"github:bufbuild/buf" = "1.32.1"
```

### Settings Reference

```toml
[settings]
locked = true                       # Require lockfile to exist
lockfile = true                     # Create/update mise.lock
experimental = true                 # Needed for some plugin features
paranoid = false                    # Don't verify checksums aggressively
github.slsa = false                 # Skip SLSA provenance verification
github.github_attestations = false  # Skip GitHub attestations
aqua.github_attestations = false    # Skip aqua GitHub attestations
aqua.cosign = false                 # Skip cosign verification
aqua.slsa = false                   # Skip aqua SLSA verification
aqua.minisign = false               # Skip minisign verification
```

These security settings are commonly disabled during development for speed. Enable them in CI/production.

### Common Tool Specs

**Node.js project:**
```toml
[tools]
node = "22.14.0"
"github:pnpm/pnpm" = "9.15.2"
```

**Node.js / Bun project:**
```toml
[tools]
node = "22.14.0"
```

Note: If the project has a `.tool-versions` file with `bun` and `deno`, mise picks those up automatically — no need to duplicate them in `.mise.toml`.

**Go project:**
```toml
[tools]
go = "1.22"
"github:sqlc-dev/sqlc" = "1.28.0"
"github:gotestyourself/gotestsum" = "1.12.0"
```

**JVM project (Maven):**
```toml
[tools]
java = "openjdk-21"
maven = "3.9.9"
```

Note: `core:java` does not generate lockfile URLs — use `lockfile = true` but omit `locked = true`. Maven uses the `aqua:` backend and does support lockfile URLs.

**JVM project (Gradle):**
```toml
[tools]
java = "openjdk-21"
```

Note: Gradle projects typically include `gradlew` wrapper — no need to install Gradle via mise.

**Python project:**
```toml
[tools]
python = "3.13.12"
"pipx:uv" = "0.10.5"
```

Note: `core:python` does not generate lockfile URLs — use `lockfile = true` but omit `locked = true`. Pin exact Python versions (e.g., `"3.13.12"` not `"3.13"`) to match the resolved lockfile entry.

**Ruby project:**
```toml
[settings]
locked = true
lockfile = true
experimental = true
paranoid = false

[tools]
ruby = "3.3.7"
```

Note: `core:ruby` supports lockfile URLs, so `locked = true` works. Pin exact patch versions (e.g., `"3.3.7"` not `"3.3"`) to match the resolved lockfile entry.

**C/autotools project:**
```toml
[settings]
lockfile = true
experimental = true
paranoid = false
```

Note: C projects typically use system-provided build tools (`gcc`, `make`, `autoconf`, `libtool`). The `.mise.toml` may have no `[tools]` section at all — it still serves as the sayt entry point. Running `mise lock` with no tools will report "No tools configured to lock" and produce no lockfile, which is expected.

**Rust project:**
```toml
[settings]
experimental = true
paranoid = false

[tools]
"cargo:cargo-audit" = "latest"
```

Note: Rust projects typically manage the toolchain via `rustup` (and optionally `rust-toolchain.toml`), not mise. Use mise only for auxiliary cargo tools. The `cargo:` backend installs tools via `cargo-binstall` and does **not** support lockfile mode (`locked = true`) since these tools are compiled from source or fetched from third-party binary caches — omit the `locked` and `lockfile` settings for projects that only use `cargo:` tools.

**Multi-language project:**
```toml
[tools]
node = "22.14.0"
go = "1.22"
"github:bufbuild/buf" = "1.32.1"
```

### Platform-Specific Stubs

sayt uses mise "tool stubs" for tools like CUE, Docker, and uvx. These have platform-specific TOML configs:

- `cue.toml` — Standard CUE stub
- `cue.musl.toml` — Alpine/musl Linux variant
- `docker.toml` / `docker.musl.toml` — Docker stub
- `uvx.toml` / `uvx.musl.toml` — Python uvx stub
- `nu.toml` / `nu.musl.toml` — Nushell stub

The musl variant is automatically selected when running on musl-based Linux (e.g., Alpine containers).

## Custom Setup Logic via `.sayt.nu`

If your project needs setup beyond what mise provides, create `.sayt.nu`:

```nushell
# .sayt.nu — Custom setup hooks
def "main setup" [] {
    # Example: install Nix packages
    nix-env -iA nixpkgs.myTool

    # Example: run database migrations
    sqlc generate
}
```

sayt automatically detects and runs `.sayt.nu setup` after the mise-based setup completes.

## Writing Good `.mise.toml` Files

1. **Pin exact versions** — Use `"22.14.0"` not `"22"` for reproducibility (especially important for lockfile matching)
2. **Always generate a lockfile** — Run `mise lock` and commit `mise.lock` to version control
3. **Use `locked = true` when possible** — But omit it when using backends that don't support URLs (see Lockfile Compatibility table)
4. **Prefer registry names** — Use `node` not `"github:nodejs/node"` when available
5. **Use `github:` prefix** — For tools not in the default mise registry
6. **Keep settings section** — Even if using defaults, be explicit about security settings
7. **Check `.tool-versions`** — If the project already has a `.tool-versions` file, mise picks those up automatically

## Lockfile Workflow

Always generate a lockfile as part of the standard setup for reproducible installs:

```bash
mise lock       # Generate mise.lock with URLs for all platforms
sayt setup      # Now installs succeed
```

The generated `mise.lock` should be committed to version control for reproducible installs across machines and CI.

### Lockfile Compatibility by Backend

Not all backends support `locked = true` (which requires download URLs in `mise.lock`):

| Backend | Lockfile entry | Has URLs | `locked = true` |
|---------|---------------|----------|-----------------|
| `core:node` | Yes | Yes | **Yes** |
| `core:go` | Yes | Yes | **Yes** |
| `core:bun` | Yes | Yes | **Yes** |
| `core:deno` | Yes | Yes | **Yes** |
| `core:ruby` | Yes | Yes | **Yes** |
| `core:java` | Yes | **No** | **No** |
| `core:python` | Yes | **No** | **No** |
| `aqua:` (maven etc) | Yes | Yes | **Yes** |
| `github:` | Yes | Usually yes | **Usually** |
| `cargo:` | **No** | No | **No** |
| `pipx:` | Yes | Varies | **Varies** |

When a project uses any tool whose backend doesn't support URLs (e.g., `core:java`, `core:python`, `cargo:`), use `lockfile = true` without `locked = true`. The lockfile still pins exact resolved versions for reproducibility — it just can't enforce download URL verification for those tools.

## Current flags

!`sayt help setup`
!`sayt help doctor`
