# SAYT CLI

Make your repo feel like it has its own DevOps team. SAYT wraps modern tooling
into a single command so you can bootstrap, build, test, and launch
with zero guesswork.

## Why SAYT?

- **Batteries included**: `setup`, `doctor`, `generate`, `lint`, `build`,
`test`, `launch`, `integrate`, `release`, and `verify` all live behind a single
entrypoint.
- **Zero drift**: Tasks re-use configuration you already use, from your vscode
setup to your docker compose files.
- **Portable**: Works anywhere nushell, docker and mise are available - macOS,
Linux, Windows (native or WSL), dev containers, CI runners.
- **Developer-first**: Every command prints the exact shell steps it executes,
making it easy to reproduce or customize workflows.

## Install

**macOS / Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/bonitao/sayt/refs/heads/main/install | sh
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/bonitao/sayt/refs/heads/main/install | iex
```

After installation, `sayt` will be available in your PATH.

## Getting started

```bash
# Trust and install tools declared in .mise.toml, then warm up auxiliary caches
sayt setup

# Run health checks for required CLIs and network access
sayt doctor

# Build & test using your .vscode/tasks.json definitions
sayt build
sayt test

# Regenerate artifacts (Dockerfiles, manifests, configs) from .say.* rules
sayt generate --force

# Launch the docker-based dev stack or run full integration tests
sayt launch
sayt integrate
```

Use `sayt help <command>` for command-specific options.

## Command overview

| Command | What it does |
| ------- | ------------- |
| `setup` | Installs toolchains via `mise`, preloads VS Code task runner, delegates to project `.sayt.nu`. |
| `generate` / `lint` | Run declarative SAY rules across `.say.{cue,yaml,yml,json,toml,nu}` to keep scaffolding in sync. |
| `build` / `test` | Execute named VS Code tasks so CLI + editor stay in lockstep. |
| `launch` / `integrate` | Bring up docker compose stacks with docker-out-of-docker support enabling powerful inception semantics. |

## Configuration magic

- Configure nothing for reasonable behavior that supports the most common
scenarios out-of-the-box.
- Drop rules in `.say.yaml`, `.say.toml`, `.say.cue`, etc. Sayt behavior can be
fully customized and the configuration can be expressed from simple toml files
to complex monorepo cue setups, and even full blown nushell code with a
`.say.nu`.
- Want to hook into custom logic? Add a `.sayt.nu` at your repo root and SAYT
automatically recurses into it.
- Leverage existing plugins and internal SAYT logic to bring powerful logic
into you codebase.

## Bring-your-own stack

- vs code tasks: build/test share the same definitions you already run
in the editor.
- docker compose: `launch` and `integrate` use your existing `compose.yaml`
targets while handling docker-out-of-docker plumbing, auth, and kubeconfig
exports automatically.
- mise-en-place: reuse your existing `.mise.toml` for describing developer tools, or hook your own custom logic for venv, flox, apt, or whatever you prefer.

<details>
<summary><strong>Extended Install Options</strong></summary>

### Using mise package manager

If you use [mise](https://mise.jdx.dev/) for tool management:

```bash
mise use -g github:bonitao/sayt
```

### Manual binary download

SAYT is distributed as a single ~600KB file in the actually-portable-format
which works on macOS, Linux, and Windows, on both arm64 and x86 architectures.

1. Download the binary from the [releases page](https://github.com/bonitao/sayt/releases)
2. Place it somewhere in your PATH (e.g., `~/.local/bin/` or `C:\Users\<you>\bin\`)
3. Make it executable (on macOS/Linux): `chmod +x sayt`

### Repository wrapper scripts

For teams who want zero external dependencies for contributors, you can commit
wrapper scripts directly in your repository. After cloning, anyone can run
`./saytw` without installing anything globally.

Download and commit these files to your repo:
- **macOS / Linux:** [`saytw`](https://raw.githubusercontent.com/bonitao/sayt/refs/heads/main/saytw) - POSIX shell wrapper
- **Windows:** [`saytw.ps1`](https://raw.githubusercontent.com/bonitao/sayt/refs/heads/main/saytw.ps1) - PowerShell wrapper

The wrappers automatically download and cache the SAYT binary on first run.

</details>

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

## Getting started

SAYT is designed for gradual adoption. We nickname the levels of adoption after engineering levels: senior, staff and principal. Let us start configuring a codebase with SAYT at senior level.

### Senior

The goal is that anyone can clone the repository source code, build and test
the code, and reproduce behaviors locally. In other words, fix the "works in my
machine" problem.

For this, we first need to capture the commands that you use locally to build
your system in a .vscode/tasks.json file, which will also become available to
vscode/cursor, etc. You can do it by hand or just add any llm to do it. Then
you can run `./sayt build` and see if it works. If you have unit tests, you can
follow the same steps to add a test task in the vscode config and then `./sayt
test`

Now you need to make sure that when another engineer clones the repo and tries
to run the same commands will not see a failure because they lack the required
tools in their machine. This time you can ask the llm to create a `.mise.toml`
if you don't already have one. Now when one runs `./sayt setup` the required
tools will be installed.

This suffices to enable the development cycle on different machines, but there
is still drift since the machines may run different operational systems, or
have different applications available, among many other factors. We solve that
by authoring a `Dockerfile` which will define a container that will serve as an
isolation layer. That file can be as simple as starting from a ubuntu image,
copying the repo into it, and running the setup and build commands we defined.
Then we add a compation `compose.yml` to it, with two services: a `launch` one
which will `up` what you defined, and an `integrate` one which will be `run`.

And that is it. Sometimes challenges will arise, maybe your development environment cannot be expressed with mise, and you are `nix` enthusiastic, for example. In the end `sayt` is just a set of verbs, and what they do can fully customized, so you could just create `.sayt.nu` file that disables the battery-included `mise` and adds custom nushell code that installs and runs nix. 

### Staff

Now we will deal with some cross cutting concerns. We will make a ci/cd, make the code debuggable, and teach our AGENTS.md about SAYT.

### Principal

We will now move from a single service into a product.
