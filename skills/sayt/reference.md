# sayt Reference — Verb, Tool, and Config Mapping

## Complete Verb → Tool → Config Mapping

| Verb | Tool | Config file | What the verb runs |
|------|------|------------|-------------------|
| `setup` | mise | `.mise.toml` | `mise trust -y -a -q && mise install` |
| `doctor` | mise, cue, docker, kind, skaffold, gcloud, crossplane | (checks PATH) | Checks each tool's availability |
| `generate` | CUE + gomplate + nushell | `.say.{cue,yaml,toml,nu}` | Runs rules from `say.generate.rules` |
| `lint` | CUE + nushell | `.say.{cue,yaml,toml,nu}` | Runs rules from `say.lint.rules` |
| `build` | CUE | `.vscode/tasks.json` | Extracts and runs the "build" labeled task via `cue export` |
| `test` | CUE | `.vscode/tasks.json` | Extracts and runs the "test" labeled task via `cue export` |
| `launch` | docker compose | `compose.yaml` + `Dockerfile` | `docker compose run --build develop` |
| `integrate` | docker compose | `compose.yaml` + `Dockerfile` | `docker compose up integrate --exit-code-from integrate` |
| `release` | goreleaser | `.goreleaser.yaml` | `goreleaser release` with passthrough flags |
| `verify` | skaffold | `skaffold.yaml` | `skaffold verify` with passthrough flags |

## Configuration File Examples

### `.mise.toml` (for `setup` / `doctor`)

```toml
[settings]
locked = true
lockfile = true
experimental = true
paranoid = false

[tools]
node = "22.14.0"
"github:pnpm/pnpm" = "9.15.2"
```

```toml
[settings]
locked = true
lockfile = true
experimental = true

[tools]
java = "openjdk-21.0"
```

```toml
[settings]
locked = true
lockfile = true
experimental = true

[tools]
go = "1.22"
"github:sqlc-dev/sqlc" = "1.28.0"
```

### `.vscode/tasks.json` (for `build` / `test`)

**Gradle (Kotlin/Java):**
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

**Go:**
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

**Node.js/pnpm (monorepo):**
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

**Python:**
```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build",
      "type": "shell",
      "command": "python",
      "args": ["-m", "build"],
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": []
    },
    {
      "label": "test",
      "type": "shell",
      "command": "pytest",
      "group": { "kind": "test", "isDefault": true },
      "problemMatcher": []
    }
  ]
}
```

### `.say.yaml` / `.say.cue` (for `generate` / `lint`)

**Disabling a built-in rule:**
```yaml
say:
  generate:
    rulemap: { "auto-cue": null }
```

**Adding a custom generate rule:**
```yaml
say:
  generate:
    rulemap:
      protobuf:
        cmds:
          - do: "buf generate"
            outputs: ["gen/"]
```

### `compose.yaml` (for `launch` / `integrate`)

```yaml
volumes:
  root-dot-docker-cache-mount: {}
services:
  develop:
    command: ./gradlew dev -t
    ports:
      - "8080:8080"
    build:
      network: host
      context: ../..
      dockerfile: services/tracker/Dockerfile
      secrets:
        - host.env
      target: debug
    volumes:
      - //var/run/docker.sock:/var/run/docker.sock
    entrypoint:
      - /monorepo/plugins/devserver/dind.sh
    secrets:
      - host.env
    network_mode: host
  integrate:
    command: "true"
    build:
      network: host
      context: ../..
      dockerfile: services/tracker/Dockerfile
      secrets:
        - host.env
      target: integrate
secrets:
  host.env:
    environment: HOST_ENV
```

### `.goreleaser.yaml` (for `release`)

**CLI tool (multi-platform binaries + Docker):**
```yaml
builds:
  - builder: zig
    targets:
      - x86_64-linux-musl
      - aarch64-linux-musl
      - x86_64-macos
      - aarch64-macos
      - x86_64-windows
      - aarch64-windows
dockers:
  - image_templates:
      - "ghcr.io/org/tool:{{ .Version }}-amd64"
    use: buildx
    build_flag_templates:
      - "--platform=linux/amd64"
docker_manifests:
  - name_template: "ghcr.io/org/tool:{{ .Version }}"
    image_templates:
      - "ghcr.io/org/tool:{{ .Version }}-amd64"
      - "ghcr.io/org/tool:{{ .Version }}-arm64"
release:
  github:
    owner: org
    name: tool
```

**Service (Docker image + skaffold deploy):**
```yaml
builds: []
dockers:
  - image_templates:
      - "gcr.io/project/service:{{ .Version }}"
publishers:
  - name: deploy
    cmd: skaffold deploy -p production
monorepo:
  tag_prefix: service-name/
  dir: services/service-name
```

**Web app (custom build + firebase deploy):**
```yaml
builds: []
publishers:
  - name: firebase
    cmd: firebase deploy
monorepo:
  tag_prefix: web/
  dir: guis/web
```

## Troubleshooting

### `sayt release` fails
- **No .goreleaser.yaml**: Create a `.goreleaser.yaml` in the project directory
- **goreleaser not installed**: Run `mise use -g goreleaser` or add to `.mise.toml`
- **No git tag**: For production releases, tag first: `git tag v1.0.0`. For testing: `sayt release --snapshot --clean`

### `sayt verify` fails
- **No skaffold.yaml**: Create a `skaffold.yaml` with a `verify:` section
- **No verify section**: Add verification containers to skaffold.yaml's `verify:` block

### `sayt setup` fails
- **Missing mise**: Install mise via `curl https://mise.jdx.dev/install.sh | sh`
- **Trust error**: sayt runs `mise trust -y -a -q` automatically, but check `.mise.toml` is valid TOML
- **Tool not found in mise registry**: Use `"github:owner/repo"` format for non-standard tools

### `sayt build` / `sayt test` fails
- **Task label not found**: Ensure `.vscode/tasks.json` has a task with the matching label
- **No build/test task**: Ensure `.vscode/tasks.json` has tasks with `"label": "build"` and `"label": "test"`
- **Task fails**: The error comes from the underlying command (gradle, go, pnpm, etc.) — fix the source code or build config

### `sayt generate` / `sayt lint` produces no output
- **No `.say.*` config**: Create a `.say.cue` or `.say.yaml` with generate/lint rules
- **Built-in rules disabled**: Check if `.say.yaml` sets rules to null

### `sayt integrate` fails
- **Docker not running**: Ensure the Docker daemon is available
- **Containers left behind**: Run `docker compose down -v` to clean up from a previous failed run
- **Build context wrong**: Check `compose.yaml` has the correct `context` and `dockerfile` paths

### `sayt doctor` shows failures
- **pkg ✗**: Install mise (macOS/Linux) or scoop (Windows)
- **cli ✗**: Missing cue or gomplate — `mise use -g cue gomplate`
- **ide ✗**: Missing cue — managed internally via mise tool stub
- **cnt ✗**: Docker not installed or daemon not running
- **k8s ✗**: Missing kind or skaffold — `mise use -g kind skaffold`

## Setting Up a New Project from Scratch

1. **Create `.mise.toml`** — Specify the runtime tools your project needs
2. **Run `sayt setup`** — Installs all tools
3. **Create `.vscode/tasks.json`** — Define `build` and `test` tasks for your language
4. **Run `sayt build && sayt test`** — Verify the inner loop works
5. **Create `Dockerfile`** — Multi-stage build with `debug` and `integrate` targets
6. **Create `compose.yaml`** — Define `develop` and `integrate` services
7. **Run `sayt integrate`** — Verify containerized tests pass
8. **(Optional)** Create `.goreleaser.yaml` for `sayt release` and/or `skaffold.yaml` for `sayt verify`
