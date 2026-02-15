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
claude plugin add bonisoft3/sayt
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

The commands, or verbs, in sayt, come in pairs, with a verb that does something and a counterpart that verify the results. You can see all of them by running `sayt --help` or learn more about any specific one with `sayt help <verb>`.


| Command | What it does |
| ------- | ------------- |
| `setup` | Install toolchains and environment, leverages mise by default, works in tandem with `doctor`. |
| `generate` | Generates code, powered by cue by default, complemented by `lint`. |
| `build`| Compile your code, kept in lockstep with vscode config by default, can be followed by `test` for extra code validation. |
| `launch` | Bring up a containerized version of the code, and coupled with `integrate` assures correct behavior, relies on docker compose by default. |
| `release` | Let others use your product and relies on `verify` to check what is out there, powered by skaffold by default. |

These verbs often can work out of the box due to the fact that sayt by default uses popular tools that may already be configured. When that is not the case, you can use any code assistant to wire up those popular tools for you, or you can use `sayt help verb --skills` to tune your assitant for the task at hand.

Also, because sayt is ultimately a set of conventions, you have convenient scape hatches to change the behavior of each verb or even the verbs themselves.

## Configuring sayt.

The simplest form of configuration for sayt is through `.sayt.yaml`. For example, it is often worth pinning the version of sayt in a repository. If if you prefer other formats, sayt will also read `.sayt.toml` or `.sayt.json`. 

Beyond syntax choice for simple declarative configuration, sayt offers advanced composition mechanisms. You can use `include` and `override` directives in your configuration, with expected semantics, or you can use `.sayt.cue` to leverage the full power of cue for configuration. Sayt config has a block for configuring sayt each itself, and one for each command. Sayt automatically validate your config with a cue schema, and you can check it out in jsonschema as well.

If you prefer to define configuration programatically or you need to do it dynamically by inspecting the environment, you can drop a `.sayt.nu` config file. In fact, all of sayt verbs default behaviors are defined in a default configuration, and you can fully adapt sayt to use your preferred semantics instead.

All these mechanisms co-exist peacefully through cuelang unification rules, but most users will never need to dive into them. It just works.

## Claude Code plugin

Sayt ships as a [Claude Code plugin](https://docs.anthropic.com/en/docs/claude-code/plugins)
that teaches Claude how to write and fix the configuration files behind each
verb and how configure sayt itself.

### What the plugin provides

| Skill | What Claude learns |
| ----- | ------------------ |
| **sayt-lifecycle** | General lifecycle knowledge — verb pairs, the seven-environment model, the TDD loop. Auto-invoked when you ask about building, testing, or deploying. |
| **sayt-cli** | How to write `.mise.toml` files with correct tool versions, settings, and platform stubs. |
| **sayt-code** | How to write `.say.cue` / `.say.yaml` — the ordered-map rule pattern, built-in generators (`auto-gomplate`, `auto-cue`), CUE basics. |
| **sayt-ide** | How to write `.vscode/tasks.json` — build/test task schema, `dependsOn` chains, per-language examples (Gradle, Go, Node/pnpm, Python, Zig). |
| **sayt-cnt** | How to write `Dockerfile` + `compose.yaml` — the `develop`/`integrate` service convention, multi-stage targets, dind helpers. |
| **sayt-k8s** | How to write `skaffold.yaml` — preview/staging/production profiles, Kind setup, Cloud Run patterns. |

The plugin also includes a **sayt-dev-loop** agent that can drive the full
setup -> doctor -> generate -> lint → build → test → launch -> integrate → release → verify lifecycle.

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

Each skill includes static reference material plus dynamic injection of
`sayt help <verb>` output, so Claude sees the exact flags available in your
installed version.

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

This suffices to enable the development cycle on different machines, but there is still drift since the machines may run different operational systems, or have different applications available, among many other factors. We solve that by authoring a `Dockerfile` which will define a container that will serve as an isolation layer. That file can be as simple as starting from a ubuntu image, copying the repo into it, and running the setup and build commands we defined. Then we add a compation `compose.yml` to it, with two services: a `launch` one which will `up` what you defined, and an `integrate` one which will be `run`.

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

### Senior Staff

We can now go from continuous integration to contnuous delivery.

</details>

### Principal

Software products are a composition of several assets, often written in different programming languages, managed by different tools, and with varying degrees of quality. There are reasons for that, some technical, some organizational and some even philosophical. The mix of inherent and accidental complexity makes this problem hard to deal with. But sayt can alleviate this pain.

Let us illustrate it with a software product that is developed by a handful of people or agents. You will typically have a frontend, a backend connected to a database and a couple microservices doing stateless or event driven computations. They can either live in a monorepo or in separated repos that can be composed in a single root with git submodules.


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

