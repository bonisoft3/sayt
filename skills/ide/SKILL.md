---
name: sayt-ide
description: >
  How to write .vscode/tasks.json for sayt build / test — task schema,
  dependsOn chains, Windows overrides, and canonical per-language patterns.
  Use when creating build tasks, test tasks, or fixing compilation failures.
user-invocable: false
---

# build / test — VS Code Tasks via CUE

`sayt build` finds the task labeled `"build"` in `.vscode/tasks.json` and runs it. `sayt test` does the same for `"test"`. `dependsOn` chains resolve automatically. Platform overrides (`windows.command`) are applied.

CUE drives the extraction and is installed via mise tool stub — no manual setup.

## Required Schema

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build",                        // must be exactly "build" or "test"
      "type": "shell",                         // must be "shell"
      "command": "pnpm",
      "args": ["run", "build"],
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": [],                    // can be empty, or ["$tsc"], ["$rustc"], ["$msCompile"]
      "dependsOn": ["install"],                // optional
      "windows": { "command": "pnpm.cmd" }     // optional per-platform override
    }
  ]
}
```

Requirements:

- Labels are **exactly** `build` and `test`. Anything else is invisible to sayt.
- `"type": "shell"` is mandatory.
- `isDefault: true` on the default build and test tasks.
- `dependsOn` targets must also be defined in `tasks` (without `isDefault`).

## Canonical Patterns

### Node.js / pnpm (monorepo with Turbo)

```json
{
  "version": "2.0.0",
  "tasks": [
    { "label": "install", "type": "shell", "command": "pnpm install --frozen-lockfile" },
    {
      "label": "build", "type": "shell",
      "command": "pnpm -C ../.. exec turbo --filter ./guis/web assemble",
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": ["$tsc"],
      "dependsOn": ["install"]
    },
    {
      "label": "test", "type": "shell",
      "command": "pnpm -C ../.. exec turbo --filter ./guis/web test",
      "group": { "kind": "test", "isDefault": true },
      "problemMatcher": ["$tsc"],
      "dependsOn": ["install"]
    }
  ]
}
```

For standalone (non-monorepo) pnpm, drop `turbo` and use `pnpm build` / `pnpm test` directly. For Bun, swap `pnpm` → `bun` and `pnpm install --frozen-lockfile` → `bun install --frozen-lockfile`.

### JVM (Gradle, with Windows override)

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build", "type": "shell",
      "command": "./gradlew",
      "windows": { "command": ".\\gradlew.bat" },
      "args": ["assemble"],
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": []
    },
    {
      "label": "test", "type": "shell",
      "command": "./gradlew",
      "windows": { "command": ".\\gradlew.bat" },
      "args": ["test"],
      "group": { "kind": "test", "isDefault": true },
      "problemMatcher": []
    }
  ]
}
```

For Maven: `mvn` with `["compile", "-pl", "<module>", "-am", "-q"]` for build and `["test", "-pl", "<module>", "-am"]` for test. No `dependsOn` needed — Maven and Gradle handle deps internally.

### Go (with code generation via dependsOn)

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build", "type": "shell",
      "command": "go",
      "args": ["build", "-o", "app"],
      "group": { "kind": "build", "isDefault": true },
      "dependsOn": ["sqlc-generate", "buf-generate"],
      "problemMatcher": []
    },
    {
      "label": "sqlc-generate", "type": "shell",
      "command": "sqlc", "args": ["generate"],
      "group": { "kind": "build" }, "problemMatcher": []
    },
    {
      "label": "buf-generate", "type": "shell",
      "command": "buf", "args": ["generate"],
      "group": { "kind": "build" }, "problemMatcher": []
    },
    {
      "label": "test", "type": "shell",
      "command": "gotestsum",
      "args": ["--format", "github-actions", "--", "./..."],
      "group": { "kind": "test", "isDefault": true },
      "problemMatcher": []
    }
  ]
}
```

For vendored Go projects, add `"-mod=vendor"` to test args and use `./hack/build` (or whatever the project's build script is) as the build command.

### Python / uv

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build", "type": "shell",
      "command": "uv", "args": ["build"],
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": []
    },
    {
      "label": "test", "type": "shell",
      "command": "uv", "args": ["run", "pytest", "-v", "--tb=short"],
      "group": { "kind": "test", "isDefault": true },
      "problemMatcher": []
    }
  ]
}
```

### Rust / Cargo

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build", "type": "shell",
      "command": "cargo", "args": ["build", "--locked"],
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": ["$rustc"]
    },
    {
      "label": "test", "type": "shell",
      "command": "cargo", "args": ["test", "--locked"],
      "group": { "kind": "test", "isDefault": true },
      "problemMatcher": ["$rustc"]
    }
  ]
}
```

`--locked` enforces `Cargo.lock`. Cargo runs unit and integration tests in one pass.

## Adapting Other Languages

For languages not shown here, map your normal terminal command into the schema above:

| Language | Build | Test | Notes |
|---|---|---|---|
| Scala / sbt | `sbt compile` | `sbt test` | For multi-module, use `sbt <module>/compile` |
| Elixir / Mix | `mix compile` (depends on `mix deps.get`) | `mix test` | Chain `deps.get` via `dependsOn` |
| Ruby / Rake | `bundle exec rake <build-task>` (depends on `bundle install`) | `bundle exec rake test` | `bundle exec rake -T` to discover tasks |
| C / autotools | `make -j$(nproc)` (depends on `autoreconf -i` → `./configure`) | `make check VERBOSE=yes` | Chain via `dependsOn`; autotools convention is `make check` |
| .NET | `dotnet build --configuration Release` | `dotnet test --configuration Release --no-build` (depends on `build`) | `problemMatcher: ["$msCompile"]` |
| Zig | `zig build` | `zig build test` | Nothing fancy needed |

Problem matchers worth knowing: `["$tsc"]` for TypeScript, `["$rustc"]` for Rust, `["$msCompile"]` for C#/MSBuild, `["$gcc"]` for C/C++, `[]` when you don't care.

## Writing Good Tasks

1. **Label exactly `build` and `test`.** Anything else is invisible to sayt.
2. **Use `"type": "shell"`.** Required.
3. **One default per group.** `isDefault: true` on the primary build and test tasks.
4. **Use `dependsOn` for prerequisites.** Code generation, dependency install, configure steps — make them separate tasks and chain them.
5. **Windows overrides for path-flavored commands.** `./gradlew` vs `.\gradlew.bat`.
6. **Match your terminal command.** If it doesn't work when you type it, wrapping it in tasks.json won't save you.
7. **Don't wire containers in here.** `build`/`test` is the app layer. If the task needs docker, the layer is wrong — use `launch`/`integrate` instead.

## Current flags

Run `sayt help build` and `sayt help test` for current flags.
