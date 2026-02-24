---
name: sayt-ide
description: >
  How to write .vscode/tasks.json — build/test task schema, dependsOn chains,
  per-language examples (Gradle, Maven, sbt, Go, Node/pnpm, Bun, Python/uv, Ruby, Elixir, .NET, Rust, C/autotools, Zig).
  Use when creating build tasks, test tasks, or fixing compilation/test failures.
user-invocable: false
---

# build / test — VS Code Tasks via CUE

`sayt build` and `sayt test` use CUE to read `.vscode/tasks.json` and run the tasks labeled "build" and "test" respectively.

## How It Works

1. `sayt build` finds the task with `"label": "build"` in `.vscode/tasks.json` via `cue export`
2. `sayt test` finds the task with `"label": "test"`
3. `dependsOn` chains are resolved and prerequisite tasks run first
4. Platform-specific overrides (e.g. `windows.command`) are applied automatically
5. The commands execute as shell commands in the project directory

CUE is managed internally via a mise tool stub — no manual installation needed.

## `.vscode/tasks.json` Schema

Every tasks.json must have:
- `"version": "2.0.0"`
- A `tasks` array with at minimum a `"build"` and `"test"` task

### Required Task Structure

```json
{
  "label": "build",          // MUST be exactly "build" or "test"
  "type": "shell",           // MUST be "shell" for sayt compatibility
  "command": "...",           // The executable to run
  "args": ["..."],           // Arguments (optional)
  "group": {
    "kind": "build",         // "build" or "test"
    "isDefault": true        // Mark as default for the group
  },
  "problemMatcher": [],      // VS Code error matching (can be empty)
  "dependsOn": ["..."]       // Prerequisite tasks (optional)
}
```

### Windows Support

Add a `windows` override for cross-platform commands:

```json
{
  "label": "build",
  "type": "shell",
  "command": "./gradlew",
  "windows": { "command": ".\\gradlew.bat" },
  "args": ["assemble"]
}
```

### Task Dependencies

Use `dependsOn` to run prerequisite tasks:

```json
{
  "label": "build",
  "type": "shell",
  "command": "go",
  "args": ["build", "-o", "app"],
  "dependsOn": ["sqlc-generate", "buf-generate"]
}
```

Dependency tasks don't need `isDefault: true` but should still be in the tasks array.

## Per-Language Examples

### Kotlin/Java (Gradle)

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build",
      "type": "shell",
      "command": "./gradlew",
      "windows": { "command": ".\\gradlew.bat" },
      "args": ["assemble"],
      "problemMatcher": [],
      "group": { "kind": "build", "isDefault": true }
    },
    {
      "label": "test",
      "type": "shell",
      "command": "./gradlew",
      "windows": { "command": ".\\gradlew.bat" },
      "args": ["test"],
      "group": { "kind": "test", "isDefault": true },
      "problemMatcher": []
    }
  ]
}
```

### Go (with code generation)

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build",
      "type": "shell",
      "command": "go",
      "args": ["build", "-o", "app"],
      "group": { "kind": "build", "isDefault": true },
      "dependsOn": ["sqlc-generate", "buf-generate"],
      "problemMatcher": []
    },
    {
      "label": "sqlc-generate",
      "type": "shell",
      "command": "sqlc",
      "args": ["generate"],
      "group": { "kind": "build" },
      "problemMatcher": []
    },
    {
      "label": "buf-generate",
      "type": "shell",
      "command": "buf",
      "args": ["generate", "../../libraries/xproto", "--template", "../../libraries/xproto/buf.go.gen.yaml", "-o", "../../libraries/xproto"],
      "group": { "kind": "build" },
      "problemMatcher": []
    },
    {
      "label": "test",
      "type": "shell",
      "command": "go",
      "args": ["run", "gotest.tools/gotestsum@v1.12.0", "-f", "github-actions", "--", "./...", "-tags=unit_test"],
      "group": { "kind": "test", "isDefault": true },
      "problemMatcher": []
    }
  ]
}
```

### Go (vendored, with build scripts)

For projects using vendored dependencies and existing build scripts (e.g., `./hack/build`):

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build",
      "type": "shell",
      "command": "./hack/build",
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": []
    },
    {
      "label": "test",
      "type": "shell",
      "command": "gotestsum",
      "args": [
        "-f", "github-actions",
        "--", "-mod=vendor", "-count=1",
        "-v", "-coverprofile=/tmp/coverage.txt",
        "-covermode=atomic", "./..."
      ],
      "group": { "kind": "test", "isDefault": true },
      "problemMatcher": [],
      "options": {
        "env": {
          "SKIP_INTEGRATION_TESTS": "1"
        }
      }
    }
  ]
}
```

Key patterns:
- **`-mod=vendor`** — Required when the project vendors its Go dependencies
- **`options.env`** — Set environment variables to control test scope (e.g., skip integration tests during unit test runs)
- **Build scripts** — If the project has a `./hack/build` or `Makefile` target, use that directly as the command instead of raw `go build`

### Node.js / pnpm (monorepo with Turbo)

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "install",
      "type": "shell",
      "command": "pnpm install --frozen-lockfile"
    },
    {
      "label": "build",
      "type": "shell",
      "command": "pnpm -C ../.. exec turbo --filter ./guis/web assemble",
      "problemMatcher": ["$tsc"],
      "group": { "kind": "build", "isDefault": true },
      "dependsOn": ["install"]
    },
    {
      "label": "test",
      "type": "shell",
      "command": "pnpm -C ../.. exec turbo --filter ./guis/web test",
      "group": { "kind": "test", "isDefault": true },
      "problemMatcher": ["$tsc"],
      "dependsOn": ["install"]
    }
  ]
}
```

### Node.js / pnpm (standalone)

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build",
      "type": "shell",
      "command": "pnpm",
      "args": ["build"],
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": ["$tsc"]
    },
    {
      "label": "test",
      "type": "shell",
      "command": "pnpm",
      "args": ["test"],
      "group": { "kind": "test", "isDefault": true },
      "problemMatcher": []
    }
  ]
}
```

### Python (with uv)

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build",
      "type": "shell",
      "command": "uv",
      "args": ["build"],
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": []
    },
    {
      "label": "test",
      "type": "shell",
      "command": "uv",
      "args": ["run", "pytest", "-v", "--tb=short"],
      "group": { "kind": "test", "isDefault": true },
      "problemMatcher": []
    }
  ]
}
```

Key patterns:
- **`uv build`** — Builds the Python package (replaces `python -m build`)
- **`uv run pytest`** — Runs pytest through uv's environment management, ensuring deps are synced

### Node.js / Bun

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "install",
      "type": "shell",
      "command": "bun",
      "args": ["install", "--frozen-lockfile"],
      "problemMatcher": []
    },
    {
      "label": "build",
      "type": "shell",
      "command": "bun",
      "args": ["run", "build"],
      "group": { "kind": "build", "isDefault": true },
      "dependsOn": ["install"],
      "problemMatcher": ["$tsc"]
    },
    {
      "label": "test",
      "type": "shell",
      "command": "bun",
      "args": ["run", "test"],
      "group": { "kind": "test", "isDefault": true },
      "dependsOn": ["install"],
      "problemMatcher": []
    }
  ]
}
```

Key patterns:
- **`--frozen-lockfile`** — Ensures `bun.lock` is respected during install
- **`dependsOn: ["install"]`** — Runs `bun install` before build/test
- **`["$tsc"]`** — Use TypeScript problem matcher when the project uses TypeScript

### Java / Maven

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build",
      "type": "shell",
      "command": "mvn",
      "args": ["compile", "-pl", "gson", "-am", "-q"],
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": []
    },
    {
      "label": "test",
      "type": "shell",
      "command": "mvn",
      "args": ["test", "-pl", "gson", "-am"],
      "group": { "kind": "test", "isDefault": true },
      "problemMatcher": []
    }
  ]
}
```

Key patterns:
- **`-pl <module> -am`** — For multi-module Maven projects, `-pl` selects the module and `-am` ("also make") builds its dependencies
- **`-q`** — Quiet mode for build (reduces noise); omit for test to see full test output
- No `dependsOn` needed — Maven handles dependency resolution internally

### Elixir (Mix)

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "deps",
      "type": "shell",
      "command": "mix",
      "args": ["deps.get"],
      "problemMatcher": []
    },
    {
      "label": "build",
      "type": "shell",
      "command": "mix",
      "args": ["compile"],
      "group": { "kind": "build", "isDefault": true },
      "dependsOn": ["deps"],
      "problemMatcher": []
    },
    {
      "label": "test",
      "type": "shell",
      "command": "mix",
      "args": ["test"],
      "group": { "kind": "test", "isDefault": true },
      "dependsOn": ["deps"],
      "problemMatcher": []
    }
  ]
}
```

Key patterns:
- **`mix deps.get`** — Fetches dependencies declared in `mix.exs`; runs as a `dependsOn` prerequisite
- **`mix compile`** — Compiles the project and all dependencies
- **`mix test`** — Runs ExUnit tests; automatically compiles if needed

### C# / .NET (dotnet CLI)

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build",
      "type": "shell",
      "command": "dotnet",
      "args": ["build", "--configuration", "Release"],
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": ["$msCompile"]
    },
    {
      "label": "test",
      "type": "shell",
      "command": "dotnet",
      "args": ["test", "--configuration", "Release", "--no-build"],
      "group": { "kind": "test", "isDefault": true },
      "dependsOn": ["build"],
      "problemMatcher": ["$msCompile"]
    }
  ]
}
```

Key patterns:
- **`--configuration Release`** — Build in Release mode for consistency
- **`--no-build`** — Skip rebuild in test since `dependsOn` already runs build
- **`["$msCompile"]`** — VS Code's built-in MSBuild/C# problem matcher for inline diagnostics
- No `restore` step needed — `dotnet build` implicitly restores NuGet packages

### Scala (sbt)

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build",
      "type": "shell",
      "command": "sbt",
      "args": ["compile"],
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": []
    },
    {
      "label": "test",
      "type": "shell",
      "command": "sbt",
      "args": ["test"],
      "group": { "kind": "test", "isDefault": true },
      "problemMatcher": []
    }
  ]
}
```

Key patterns:
- **Module targeting** — For multi-module projects, use `sbt <module>/compile` and `sbt <module>/test` (e.g., `kernelJVM/compile`) to build only the target module
- **No `dependsOn`** — sbt handles dependency resolution and compilation internally
- **JVM startup** — sbt has significant JVM startup time; consider using sbt's interactive shell (`sbt` then `~compile`) for development

### Ruby (Bundler/Rake)

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "install",
      "type": "shell",
      "command": "bundle",
      "args": ["install"],
      "problemMatcher": []
    },
    {
      "label": "build",
      "type": "shell",
      "command": "bundle",
      "args": ["exec", "rake", "package:all"],
      "group": { "kind": "build", "isDefault": true },
      "dependsOn": ["install"],
      "problemMatcher": []
    },
    {
      "label": "test",
      "type": "shell",
      "command": "bundle",
      "args": ["exec", "rake", "test"],
      "group": { "kind": "test", "isDefault": true },
      "dependsOn": ["install"],
      "problemMatcher": []
    }
  ]
}
```

Key patterns:
- **`bundle exec rake`** — Always run rake through bundler to ensure the correct gem versions
- **`dependsOn: ["install"]`** — Runs `bundle install` before build/test
- **Check available rake tasks** — Run `bundle exec rake -T` to discover the project's actual build and test task names (e.g., `package:all`, `test`, `spec`, `build`)

### C / autotools

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "configure",
      "type": "shell",
      "command": "autoreconf",
      "args": ["-i"],
      "problemMatcher": []
    },
    {
      "label": "run-configure",
      "type": "shell",
      "command": "./configure",
      "args": ["--disable-docs", "--with-oniguruma=builtin"],
      "dependsOn": ["configure"],
      "problemMatcher": []
    },
    {
      "label": "build",
      "type": "shell",
      "command": "make",
      "args": ["-j4"],
      "group": { "kind": "build", "isDefault": true },
      "dependsOn": ["run-configure"],
      "problemMatcher": []
    },
    {
      "label": "test",
      "type": "shell",
      "command": "make",
      "args": ["check", "VERBOSE=yes"],
      "group": { "kind": "test", "isDefault": true },
      "dependsOn": ["build"],
      "problemMatcher": []
    }
  ]
}
```

Key patterns:
- **Multi-step dependency chain** — autotools projects need `autoreconf -i` → `./configure` → `make` → `make check`, each as a separate task linked by `dependsOn`
- **`./configure` args vary** — Check the project's `README` or `configure.ac` for available flags (e.g., `--disable-docs`, `--with-oniguruma=builtin`)
- **`make check` vs `make test`** — autotools convention is `make check`; use `VERBOSE=yes` for detailed test output
- **Git submodules** — If the project uses git submodules (e.g., for vendored libraries), run `git submodule update --init` before building

### Rust (Cargo)

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build",
      "type": "shell",
      "command": "cargo",
      "args": ["build", "--locked"],
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": ["$rustc"]
    },
    {
      "label": "test",
      "type": "shell",
      "command": "cargo",
      "args": ["test", "--locked"],
      "group": { "kind": "test", "isDefault": true },
      "problemMatcher": ["$rustc"]
    }
  ]
}
```

Key patterns:
- **`--locked`** — Ensures `Cargo.lock` is respected (fails if lock file is out of date)
- **`["$rustc"]`** — VS Code's built-in Rust problem matcher parses `rustc` error output for inline diagnostics
- Cargo runs both unit tests (in-source `#[cfg(test)]` modules) and integration tests (`tests/` directory) with a single `cargo test`

### Zig

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build",
      "type": "shell",
      "command": "zig",
      "args": ["build"],
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": []
    },
    {
      "label": "test",
      "type": "shell",
      "command": "zig",
      "args": ["build", "test"],
      "group": { "kind": "test", "isDefault": true },
      "problemMatcher": []
    }
  ]
}
```

## Writing Good Tasks

1. **Label exactly "build" and "test"** — sayt looks for these exact labels
2. **Use `"type": "shell"`** — Required for sayt compatibility
3. **Set `isDefault: true`** — Mark one build and one test task as default
4. **Use `dependsOn`** — For code generation or install steps that must run first
5. **Add `problemMatcher`** — Helps VS Code parse errors (use `["$tsc"]` for TypeScript, `[]` otherwise)
6. **Add `windows` overrides** — If the command differs on Windows (e.g., `gradlew` vs `gradlew.bat`)
7. **Keep it simple** — The task should run the same command you'd type in the terminal

## Interpreting Results

- **Build success**: The underlying compiler/bundler exited 0
- **Build failure**: Read the compiler output — fix the source code
- **Test success**: All unit tests passed
- **Test failure**: Read test output for assertion failures and stack traces
- **Task label not found**: Ensure `.vscode/tasks.json` has a task with the matching label

## Current flags

!`sayt help build`
!`sayt help test`
