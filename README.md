# SAYT CLI

Sayt is a small tool that covers a large part of the concerns that arise during modern software development. It codifies the learnings from multiple journeys of simple mvps to unicorn companies, with a special eye towards making it up-scalable and down-scalable so you can do go through that whole journey as well.

It can be used by both ai agentics and human beings, in either scenario it will give you consistent and efficient flows that will speed up both your internal development cycle and the larger product iteration loops, spawning from small microservices to large monorepos.

Sayt overlaps with several tools with more narrow scopes, such as bazel, docker, garden, tilt or skaffold.

## Why SAYT?

- **Batteries included**: sayt is highly configurable, but it comes with powerful defaults that can cover your whole software development lifecycle.
- **Zero drift**: tasks re-use configuration you already use, from your vscode
setup to your docker compose files.
- **Portable**: works anywhere nushell and docker are available - macOS,
Linux, Windows (native or WSL), dev containers, CI runners.
- **Developer-first**: sayt shows what it is doing and you can take over control at any time.

## Install

**Mac / Linux / WSL:**
```bash
curl -fsSL https://raw.githubusercontent.com/bonisoft3/sayt/refs/heads/main/install | sh
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/bonisoft3/sayt/refs/heads/main/install | iex
```

After installation, `sayt` will be available in your PATH.

**Claude Code (plugin):**
```bash
claude plugin marketplace add bonisoft3/sayt
claude plugin install sayt@bonisoft3-sayt
```

<details>
<summary><strong>Extended Install Options</strong></summary>

### GitHub Actions

```yaml
- uses: bonisoft3/sayt/.github/actions/sayt/install@main
```

### Using mise package manager

If you use [mise](https://mise.jdx.dev/) for tool management:

```mise use -g github:bonisoft3/sayt```

### Manual binary download

**macOS / Linux:**
```bash
curl -fsSL -o sayt "https://github.com/bonisoft3/sayt/releases/latest/download/sayt-$(uname -s | tr A-Z a-z)-$(uname -m)"
chmod +x sayt && command -v xattr >/dev/null && xattr -d com.apple.quarantine sayt
mv sayt ~/.local/bin/
```

**Windows (PowerShell):**
```powershell
curl -o sayt.exe https://github.com/bonisoft3/sayt/releases/latest/download/sayt-windows-x64.exe
Move-Item sayt.exe "$env:LOCALAPPDATA\Microsoft\WindowsApps\"
```

### Repository wrapper scripts

For teams who want zero external dependencies for contributors, you can commit
wrapper scripts directly in your repository. After cloning, anyone can run
`./saytw` without installing anything globally.

Download and commit these files to your repo:
- **macOS / Linux:** [`saytw`](https://raw.githubusercontent.com/bonisoft3/sayt/refs/heads/main/saytw) - POSIX shell wrapper
- **Windows:** [`saytw.ps1`](https://raw.githubusercontent.com/bonisoft3/sayt/refs/heads/main/saytw.ps1) - PowerShell wrapper

The wrappers automatically download and cache the SAYT binary on first run.

### Embedded in your repository (submodule or copy)

Since sayt is fully relocatable, you can embed it directly in your repository.
The binary auto-detects local mode when `sayt.nu` is colocated, so all scripts
and tool stubs are resolved from the embedded directory — no distribution
download needed.

**As a git submodule:**
```bash
git submodule add https://github.com/bonisoft3/sayt plugins/sayt
```

**As a plain copy:**
```bash
git clone --depth 1 https://github.com/bonisoft3/sayt /tmp/sayt
cp -r /tmp/sayt plugins/sayt
rm -rf plugins/sayt/.git
```

Run sayt from the embedded directory:
```bash
./plugins/sayt/saytw setup
./plugins/sayt/saytw build
```

For CI with GitHub Actions, point `wrapper-path` to the embedded directory:
```yaml
- uses: ./plugins/sayt/.github/actions/sayt/install
  with:
    wrapper-path: plugins/sayt
```

### Self-management flags

If you already have access to sayt, via wrapper or installation, these flags provide convenient shortcuts:

**Install sayt to your user directory:**
```bash
# Installs to ~/.local/bin (Unix) or %LOCALAPPDATA%\Programs\sayt (Windows)
sayt --install
```

**Install sayt system-wide for all users:**
```bash
# Installs to /usr/local/bin (Unix) or C:\Program Files\sayt (Windows)
# Requires sudo (Unix) or Administrator (Windows)
sudo sayt --install --global
```

**Add wrapper scripts to your repository:**
```bash
# Downloads saytw and saytw.ps1, then commits them to git
sayt --commit
```

**Bootstrap wrapper scripts without installing sayt globally:**
```bash
# One-liner: pipe saytw to sh with --commit flag
curl -fsSL https://raw.githubusercontent.com/bonisoft3/sayt/refs/heads/main/saytw | sh -s -- --commit
```

This downloads and runs sayt via the wrapper, which then commits the wrapper scripts to your repo - no global installation needed.

### Using with a command runner

Options that don't add `sayt` to your PATH — such as the wrapper scripts or an
embedded submodule — pair naturally with any command runner. For example, with
[just](https://just.systems):

```just
[no-cd]
sayt target *args:
  nu {{justfile_directory()}}/plugins/sayt/sayt.nu {{target}} {{args}}
```

This lets you run `just sayt build`, `just sayt test`, etc. from anywhere in the
repository without a global install.

</details>

## Getting started

Let us start teaching sayt how to compile your code. By default, it will piggyback on vscode configuration. If you already have it configured with a `.vscode/tasks.json`, you can simply do `sayt build`. If not, you can ask your favorite ai or search engine for help.

```bash
claude -p "Create .vscode/tasks.json with a shell 'build' task for this project." --allowedTools "Read,Write,Edit,Glob,Grep"
sayt build
```

And you can repeat the steps to add a test task that will run unit tests.

```bash
claude -p "Create .vscode/tasks.json with a shell 'test' task for this project that will run all the unit tests." --allowedTools "Read,Write,Edit,Glob,Grep"
sayt test
```

If you are using the sayt claude plugin, that is even easier, just tell it "configure sayt for build and test, verify both are working" and let claude do its magic.

This will give you uniform calling for all your project that you can use everywhere, in your CI, your documentation, your AGENTS.md or your muscle memory. Beyond build and test, sayt offers you several other verbs with integrated and efficient implementations encoding the best practices of the tools you already know and love.

## Command overview

The commands, or verbs, in sayt, come in pairs, with a verb that does something and a counterpart that verifies the results. You can see all of them by running `sayt --help` or learn more about any specific one with `sayt help <verb>`.


| Command | What it does |
| ------- | ------------- |
| `setup` | Install toolchains and environment, leverages mise by default, works in tandem with `doctor`. |
| `generate` | Generates code, powered by cue by default, complemented by `lint` for validation. |
| `build`| Compile your code, kept in lockstep with vscode config by default, can be followed by `test` for extra code validation. |
| `launch` | Bring up a containerized version of the code, and coupled with `integrate` assures correct behavior, relies on docker compose by default. |
| `release` | Let others use your product and relies on `verify` to check what is out there, powered by goreleaser by default. |

These verbs often can work out of the box due to the fact that sayt by default uses popular tools that may already be configured. When that is not the case, you can use any code assistant to wire up those popular tools for you, or you can use `sayt help verb --skills` to tune your assitant for the task at hand.

Also, because sayt is ultimately a set of conventions, you have convenient scape hatches to change the behavior of each verb or even the verbs themselves.

## Configuring sayt.

The simplest form of configuration for sayt is through `.say.yaml`. If you prefer other formats, sayt will also read `.say.toml` or `.say.json`.

Beyond syntax choice for simple declarative configuration, sayt offers advanced composition through `.say.cue`, which leverages the full power of cue for configuration. Sayt config has a block for configuring sayt itself, and one for each command. Sayt automatically validates your config with a cue schema.

If you prefer to define configuration programmatically or you need to do it dynamically by inspecting the environment, you can drop a `.say.nu` config file — a [nushell](https://www.nushell.sh/) script that works identically across macOS, Linux, and Windows. In fact, all of sayt's verb default behaviors are defined in a default configuration, and you can fully adapt sayt to use your preferred semantics instead.

All these mechanisms co-exist peacefully through cuelang unification rules, but most users will never need to dive into them. It just works.

### Verb dispatch

To override a verb, set `do` directly under it:

```yaml
say:
  build:
    do: "cargo build"
```

This replaces the built-in behavior for that verb. For example, `sayt build` will now run `cargo build` instead of the default vscode-based build.

<details>
<summary><strong>Advanced: rulemap dispatch</strong></summary>

Under the hood, each verb is configured as an ordered map of **rules**. A rule has a list of commands to execute and an optional `stop` flag:

```yaml
say:
  build:
    rulemap:
      my-build:
        stop: true
        cmds:
          - do: "cargo build"
```

When `stop: true`, dispatch halts after the rule executes. When `stop` is absent or `false`, dispatch continues to the next rule. Built-in rules for verbs like `build`, `test`, and `setup` default to `stop: true`. Code generation and lint rules default to run-all, so multiple generators and linters compose naturally.

Rules are evaluated in `priority` order (lower first, default 0). You can override, extend, or remove built-in rules by referencing their key in the rulemap:

```yaml
say:
  build:
    rulemap:
      builtin: null          # remove the default vscode-based build
      my-build:
        stop: true
        cmds:
          - do: "cargo build"
```

</details>

### Lint rules

The `lint` verb runs all rules and ships with three built-in types. By default, `auto-cue` validates `.cue` schema files against their target files. You can add declarative copy and shared checks without writing any scripts:

```yaml
say:
  lint:
    # Guarantee two files stay byte-for-byte identical
    copy: ["src/config", "deploy/config"]

    # Guarantee a regex-captured value matches across files
    shared:
      pattern: "v\\d+\\.\\d+\\.\\d+"
      files: ["VERSION", "package.json", "config.cue"]
```

Multiple checks use list syntax:

```yaml
say:
  lint:
    copy:
      - ["src/config", "deploy/config"]
      - ["lib/schema.sql", "test/schema.sql"]
    shared:
      - pattern: "v\\d+\\.\\d+\\.\\d+"
        files: ["VERSION", "package.json"]
      - pattern: "\\d+\\.\\d+\\.\\d+"
        files: ["VERSION", "plugin.json"]
```

CUE users get type annotations (`#copy`, `#shared`, `#vet`) for use in rulemap entries. Custom lint rules work the same as other verbs — add entries to `rulemap` with a `cmds` block.

## Claude Code plugin

Sayt ships as a [Claude Code plugin](https://docs.anthropic.com/en/docs/claude-code/plugins)
that teaches Claude how to write and fix the configuration files behind each
verb and how configure sayt itself.

### What the plugin provides

Each skill corresponds to a verb pair and is named after the environment where that pair most commonly executes:

| Skill | Verb pair | What Claude learns |
| ----- | --------- | ------------------ |
| **sayt-cli** | `setup` / `doctor` | How to write `.mise.toml` files with correct tool versions, settings, and platform stubs. |
| **sayt-code** | `generate` / `lint` | How to write `.say.cue` / `.say.yaml` — the ordered-map rule pattern, built-in generators (`auto-gomplate`, `auto-cue`), built-in lint rules (`#copy`, `#shared`, `#vet`), CUE basics. |
| **sayt-ide** | `build` / `test` | How to write `.vscode/tasks.json` — build/test task schema, `dependsOn` chains, per-language examples (Gradle, Go, Node/pnpm, Python, Zig). |
| **sayt-cnt** | `launch` / `integrate` | How to write `Dockerfile` + `compose.yaml` — the `launch`/`integrate` service convention, multi-stage targets, dind helpers. |
| **sayt-k8s** | `release` / `verify` | How to write `skaffold.yaml` and `.goreleaser.yaml` — goreleaser for artifact publishing, skaffold for K8s deployment, preview/production profiles. |

The plugin also includes a **sayt-dev-loop** agent that can drive the full
setup → doctor → generate → lint → build → test → launch → integrate → release → verify lifecycle.

### Usage

The skills activate automatically based on context. Ask Claude about any
development lifecycle concern and it will draw on the relevant skill:

```
> help me write a .vscode/tasks.json for this Go project
> the integration tests are failing, can you fix the compose.yaml?
> set up this repo with sayt from scratch
```

To use the sayt-dev-loop agent explicitly:

```
> use the sayt-dev-loop agent to get this project building and passing tests
```

## Using sayt effectively

SAYT is designed for gradual adoption. We nickname the levels of adoption after engineering levels: senior, staff, principal and distinguished. Let us start configuring a codebase with SAYT at senior level.

### Senior

The goal is that anyone can clone the repository source code, build and test the code, and reproduce behaviors locally. In other words, fix the "works in my machine" problem.

For this, we first need to capture the commands that you use locally to build your system in a .vscode/tasks.json file, which will also become available to vscode/cursor, etc. You can do it by hand or just add any llm to do it. Then you can run `sayt build` and see if it works. If you have unit tests, you can follow the same steps to add a test task in the vscode config and then `sayt test`

Now you need to make sure that when another engineer clones the repo and tries
to run the same commands will not see a failure because they lack the required
tools in their machine. This time you can ask the llm to create a `.mise.toml`
if you don't already have one. Now when one runs `sayt setup` the required
tools will be installed. Finally, do `sayt --commit` to get `./saytw` in the repository root and then in a new machine running `./saytw --install` will install sayt for the local user.

This suffices to enable the development cycle on different machines, but there is still drift since the machines may run different operational systems, or have different applications available, among many other factors. We solve that by authoring a `Dockerfile` which will define a container that will serve as an isolation layer. That file can be as simple as starting from a ubuntu image, copying the repo into it, and running the setup and build commands we defined. Then we add a companion `compose.yaml` to it, with two services: a `launch` one which will `up` what you defined, and an `integrate` one which will be `run`.

And that is it. Sometimes challenges will arise, maybe your development environment cannot be expressed with mise, and you are `nix` enthusiastic, for example. In the end `sayt` is just a set of verbs, and what they do can fully customized, so you could just create `.sayt.nu` file that disables the battery-included `mise` flow and adds custom nushell code that installs and runs nix.

### Staff

Now we will deal with some cross cutting concerns. We will make a ci/cd, make the code debuggable,

Since `sayt integrate` already runs your integration tests inside containers,
the simplest CI is just running the same command:

```yaml
steps:
  - uses: actions/checkout@v4
  - run: ./saytw integrate
```

This works, but it builds the Docker image from scratch on every run. For faster CI you can use the [docker/bake-action](https://github.com/docker/bake-action) to build and cache the `integrate` target, then run it with `docker compose run`:

```yaml
steps:
  - uses: docker/setup-buildx-action@v3
  - uses: docker/bake-action@v5
    with:
      targets: integrate
      load: true
      set: |
        *.cache-from=type=gha
        *.cache-to=type=gha,mode=max
  - uses: actions/checkout@v4
  - run: docker compose run integrate
```

This idiom is packaged as the `sayt/integrate` action with several other goodies. You can read the detailed instructions on how to to configure the action in advanced mode where it will leverage a powerful docker-out-of-docker idiom and docker bake to cache even the run step itself as a docker layer.

<details>
<summary><strong>Advanced CI: docker-out-of-docker</strong></summary>

The advanced mode of `sayt/integrate` loads `docker-bake.override.hcl` and
enables sayt's powerful docker-out-of-docker idioms. This lets you run the full integration flow inside a CI Dockerfile target.

```hcl
variable "CACHE_SCOPE" {
  default = ""
}

function "cache_from" {
  params = [name]
  result = CACHE_SCOPE != "" ? [
    "type=gha,scope=main-${name}",
    "type=gha,scope=${CACHE_SCOPE}-${name}",
  ] : []
}

function "cache_to" {
  params = [name]
  result = CACHE_SCOPE != "" ? [
    "type=gha,mode=max,scope=${CACHE_SCOPE}-${name}"
  ] : []
}

# Outer target: built by the CI action with docker buildx bake
target "ci" {
  secret     = ["id=host.env,env=HOST_ENV"]
  network    = "host"
  context    = "."
  cache-from = cache_from("ci")
  cache-to   = cache_to("ci")
  dockerfile-inline = <<-EOF
    FROM bonisoft3/sayt:ci AS ci
    COPY . .
    RUN --mount=type=secret,id=host.env,required dind.sh sayt integrate
  EOF
}

# Inner target: built inside dind.sh where ACTIONS_CACHE_URL is available
target "integrate" {
  cache-from = cache_from("integrate")
  cache-to   = cache_to("integrate")
}
```

The `dind.sh` helper starts a scoped Docker daemon inside the container, so
`docker compose` and `docker buildx` work without privileged mode or host
socket mounting. Use the action with `mode: advanced`:

```yaml
- uses: bonisoft3/sayt/.github/actions/sayt/integrate@main
  with:
    mode: advanced
```

This gives you a fully hermetic CI where the build, test, and integration
steps all happen within a single reproducible container image. You can even run it locally with `sayt integrate --bake --target ci` or with even more fidelity as `act -j ci` if you configure it as a github workflow job named ci and install the act local runner.

</details>

### Senior Staff

We can now go from continuous integration to continuous delivery. The `release` verb packages and publishes your artifacts. It is powered by goreleaser by default, which handles versioning, changelog generation, and artifact publishing in one step.

```bash
sayt release
```

Once a release is out, `verify` checks that what you published actually works. It runs against the latest released version, not the local source, so it validates the real artifact your users receive. A typical verify step fetches the published install script, installs into a temp directory, and smoke-tests the binary:

```bash
sayt verify
```

Together, `release` and `verify` close the delivery loop. Wire them into your CI after `integrate` passes and you have a complete pipeline from commit to verified release.

<details>
<summary><strong>Releasing services to Kubernetes</strong></summary>

For services that land in Kubernetes, goreleaser can elegantly delegate to skaffold for the deployment step. In your `.goreleaser.yaml`, add a custom publisher that invokes skaffold with the tag goreleaser just built:

```yaml
publishers:
  - name: skaffold
    cmd: skaffold run -p production --tag={{ .Tag }}
```

This keeps goreleaser as the single release entrypoint while letting skaffold handle the Kubernetes-specific concerns — image pushing, manifest rendering, and rolling deployment.

</details>

<details>
<summary><strong>Configuring verify</strong></summary>

The `verify` verb has no default implementation — it is a no-op until you configure it. This is intentional: what "verification" means varies widely between projects. You configure it like any other verb through `.say.yaml` or `.say.cue`:

```yaml
say:
  verify:
    do: "skaffold verify -p production"
```

For Kubernetes services, delegating to `skaffold verify` is a natural fit since skaffold already knows your deployment topology and can run verification containers against the live environment.

</details>

### Principal

Software products are a composition of several assets, often written in different programming languages, managed by different tools, and with varying degrees of quality. There are reasons for that, some technical, some organizational and some even philosophical. The mix of inherent and accidental complexity makes this problem hard to deal with. But sayt can alleviate this pain.

Let us illustrate it with a software product that is developed by a handful of people or agents. You will typically have a frontend, a backend connected to a database and a couple microservices doing stateless or event driven computations. They can either live in a monorepo or in separated repos that can be composed in a single root with git submodules.

The key insight is that each service is just a directory with its own sayt configuration. A Go API, a React frontend, and a Python worker each have their own `.vscode/tasks.json`, `.mise.toml`, `Dockerfile`, and `compose.yaml`. Running `sayt build` in any of them does the right thing for that technology stack. At this level, nothing changes from what a senior engineer already set up — each directory is self-contained.

The principal concern is bringing these services together into a product. For this, you create a product directory — a thin glue layer that references the individual services without duplicating their configuration:

```
monorepo/
  services/api/           # Go backend — sayt build/test here
  services/worker/        # Python worker — sayt build/test here
  guis/web/               # React frontend — sayt build/test here
  products/todoapp/       # glue directory — sayt launch/integrate here
    skaffold.yaml
    compose.yaml
    overlays/
      preview/            # K8s manifests for local kind cluster
      production/         # Crossplane manifests for cloud deploy
```

The `skaffold.yaml` in the product directory uses `requires` to compose service-level skaffold configs:

```yaml
requires:
  - configs: [ "services_api" ]
    path: ../../services/api/skaffold.yaml
  - configs: [ "services_worker" ]
    path: ../../services/worker/skaffold.yaml
  - configs: [ "guis_web" ]
    path: ../../guis/web/skaffold.yaml
```

This keeps each service's build definition local to its own directory while the product directory only describes how they communicate once deployed — port forwarding, networking, shared databases, environment overlays. It is infrastructure-as-code in YAML: the product directory is declarative glue, not application logic.

With this structure, `sayt launch` in the product directory brings up the full stack locally via `skaffold dev`, and `sayt integrate` runs end-to-end tests against it. Individual service teams still run `sayt build` and `sayt test` in their own directories for fast feedback.

<details>
<summary><strong>Advanced: publishing with copybara</strong></summary>

A monorepo gives you atomic cross-service changes, but sometimes parts of it need to live in public repositories — an open-source tool, a client SDK, or the product itself. Copybara solves this by syncing subdirectories to external repos while rewriting paths and filtering files.

A `copy.bara.sky` at the repo root defines workflows for each published subset. For a single directory like a shared plugin:

```starlark
struct(
    name = "my-plugin",
    destination = "git@github.com:myorg/my-plugin.git",
    origin_files = ["plugins/my-plugin/**"],
    transformations = [core.move("plugins/my-plugin", "")],
    mode = "ITERATIVE",
)
```

This publishes `plugins/my-plugin/` as the root of a standalone repo, rewriting paths so it looks independent. For the full product, you include multiple directories:

```starlark
struct(
    name = "todoapp",
    destination = "git@github.com:myorg/todoapp.git",
    origin_files = [
        "services/api/**",
        "services/worker/**",
        "guis/web/**",
        "products/todoapp/**",
        "libraries/**",
    ],
    mode = "SQUASH",
)
```

Copybara fits naturally into the `release` verb. Configure it so that when a service or product is released, copybara syncs the relevant subset to its public repo:

```yaml
say:
  release:
    do: "copybara copy.bara.sky my-plugin"
```

The monorepo remains the source of truth, and the public repos are derived views. This lets you develop with the convenience of a monorepo while publishing with the accessibility of standalone repos.

</details>

### Distinguished

We will now fully optimize the tdd loop on all levels by introducing advanced code generation.

## Contributing

- SAYT is written in nushell with high portability in mind. It is an elegant
middle ground between shell scripts and a full blown programming language, and
LLMs are reasonably good at driving it.
- SAYT internally leverages cuelang for its configuration mechanism and pure
data manipulation tasks involving json/toml/yaml due to its conciseness and
strong guarantees.
- SAYT relies on docker for providing isolation, and it stays compatible with
podman.
- SAYT is relocatable. This means that the source code directory can be moved
around and embedded in other codebases. Because of that it cannot rely on repo
level roots, as those demanded by cuelang and golang imports. Everything must
be expressible through relative paths.
- SAYT aims to be small and readable, with its core logic clocking under <1k
loc. It leverages mise as a gateway to other powerful tools to make this possible.

### Releasing

Sayt is developed in the [worldsense/trash](https://github.com/worldsense/trash) monorepo under `plugins/sayt/` and synced to this repo via copybara. To cut a release:

1. **Determine version** — run `sayt release --dry-run` to see what git-cliff computes from conventional commits (e.g. `v0.1.0`).
2. **Update version files** — edit `VERSION` and all copies to match, verify with `sayt lint`.
3. **Merge** — open a PR and merge. Wait for copybara to sync to `bonisoft3/sayt`.
4. **Tag** — create and push the version tag on `bonisoft3/sayt`. The `cd.yml` workflow triggers on the tag push, runs goreleaser, and publishes the GitHub release with binaries.

