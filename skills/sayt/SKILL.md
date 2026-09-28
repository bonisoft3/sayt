---
name: sayt-lifecycle
description: >
  Unified development lifecycle tool. Use when the user asks about building,
  testing, setting up, deploying, or configuring a development environment.
  Teaches how to write and fix the configuration files behind each verb
  and how to configure sayt itself.
allowed-tools: Bash(sayt:*)
---

# sayt-lifecycle — Unified Development Lifecycle

sayt is a small CLI that provides consistent verbs for the entire software development lifecycle. It reuses configuration you already have (`.mise.toml`, `.vscode/tasks.json`, `.say.yaml`, `compose.yaml`, `skaffold.yaml`, `.goreleaser.yaml`) so there is zero drift between your IDE, CI, and terminal.

## The Real Verbs

The complete, definitive list:

| Verb pair | Layer | Underlying tools | Config file |
|-----------|-------|------------------|-------------|
| `sayt setup` / `sayt doctor` | Toolchain | [mise](https://mise.jdx.dev/) | `.mise.toml` + `mise.lock` |
| `sayt generate` / `sayt lint` | Static | [CUE](https://cuelang.org/), [gomplate](https://gomplate.ca/), plus any static checker | `.say.cue` / `.say.yaml` |
| `sayt build` / `sayt test` | App | whatever your language uses, via VS Code tasks | `.vscode/tasks.json` |
| `sayt launch` / `sayt integrate` | Stack (containers) | [docker compose](https://docs.docker.com/compose/) | `Dockerfile` + `compose.yaml` |
| `sayt release` / `sayt verify` | Public | [goreleaser](https://goreleaser.com/) + [skaffold](https://skaffold.dev/) | `.goreleaser.yaml` / `skaffold.yaml` |

**Anything else is not a sayt verb.** If someone tells you to run `sayt <anything-not-above>`, it's wrong. Verbs sayt does not have:

| Non-verb | What the user probably wants |
|---|---|
| `vet` | `lint` |
| `preview` | `skaffold dev -p preview` directly |
| `stage` | `skaffold run -p staging` directly |
| `publish` | `release` (make work public via goreleaser) |
| `setup-butler` | `setup` |
| `develop` | `launch` (containerized dev) or `build`/`test` (app dev) |
| `loadtest` | `verify` customized with a load test step |
| `observe` | Direct tool invocation (`kubectl logs`, `docker compose logs`, etc.) |

The verbs don't need to cover every use case. When a real verb doesn't fit, the agent is free to either:

1. **Customize the verb** — edit `.say.yaml`, `.vscode/tasks.json`, `compose.yaml`, `.goreleaser.yaml`, etc. so the existing verb covers the new case. Prefer this when the case is reusable.
2. **Use a direct command** — `skaffold dev -p preview`, `docker compose logs`, `kubectl exec`, `mise exec -- <tool>`, etc. Prefer this for one-off investigation.

## Seven-Environment Model

sayt organizes the development lifecycle into seven environments, each adding a layer of confidence. Run `sayt doctor` to see which ones are ready:

1. **pkg** — Package manager (mise). Tools installed and available.
2. **cli** — CLI tools (cue, gomplate). Code generation and validation work.
3. **ide** — IDE integration (CUE + `.vscode/tasks.json`). Build and test tasks run from your editor.
4. **cnt** — Container (docker). Code runs identically across machines.
5. **k8s** — Kubernetes (kind, skaffold). Full-stack preview deployments work.
6. **cld** — Cloud (gcloud). Staging deployment is live.
7. **xpl** — Crossplane. Production infrastructure is managed as code.

## How sayt Reuses Existing Config

sayt does **not** invent new configuration formats: each verb runs the tool that already owns its layer, from that tool's own file. What each verb runs, and from which file, is [reference.md](./reference.md); what `setup` deliberately leaves out is [sayt-cli](../cli/SKILL.md#what-setup-does-and-does-not-do). Which pair to run for a given change, and the quick commands per layer, are the **sayt-tdd** skill. No verb gates any other.

## Configuring sayt

`.say.yaml` (or `.say.toml`, `.say.json`), `.say.cue` and `.say.nu` (a nushell script whose output is merged in) unify with sayt's `config.cue`: one block for sayt itself (`self`) and one per verb, validated, with each verb's built-in behavior a default you can replace. `say.self.version` pins the sayt a repository expects; an invoked sayt of another version re-execs itself through the colocated `saytw` with `SAYT_VERSION` set to the pin.

**Rules.** `do:` under a verb replaces its built-in. Underneath, every verb is an ordered map of rules, each a list of commands:

```yaml
say:
  build:
    rulemap:
      builtin: null          # drop the vscode-based build
      my-build:
        stop: true
        cmds: [{ do: "cargo build" }]
```

Rules run in `priority` order (lower first, default 0, stable by name); referencing a built-in key modifies it and `null` removes it ([the ordered-map pattern](../code/SKILL.md#the-ordered-map-pattern)). `stop: true` ends dispatch after that rule: the built-ins of the single-action verbs stop, while the `generate` and `lint` built-ins do not, so generators and linters compose. The first failing rule ends the verb; `keep_going: true` on a verb whose rules are independent tools runs every rule, reports each failure by name and exits 1 after the last, while the commands within one rule still stop at their first failure. A script takes precedence over the rules: `.sayt.<verb>.nu`, or `.sayt.nu` defining `main <verb>`.

**Three dimensions.** The vocabulary is fixed, but three flags change what a verb does; the positional form is sugar over them:

| Flag | Changes | Use it for |
|---|---|---|
| `--directory` | which configuration files are active | a self-contained unit with its own `.say.yaml`, `tasks.json`, `compose.yaml`, `.mise.toml` |
| `--platform` (`-w`), or `verb@platform` | which rules run: those whose `platform` matches | the same operation landing elsewhere |
| a verb in `say.self.verbs` | what the action means | an operation no built-in verb fits |

Platform defaults per pair: `setup`/`doctor` → `bare`, `generate`/`lint` → `repo`, `build`/`test` → `local`, `launch`/`integrate` → `docker`, `release`/`verify` → `preview`. Any string names a platform, and a rule with no `platform` runs only on its verb's default. Precedence: `--platform`, then `verb@platform`, then `say.<verb>.flags: "--platform x"`, then `say.self.flags`, then the default; the result is `$env.SAYT_PLATFORM` for the verb script. A custom verb is configured like a built-in one:

```yaml
say:
  self: { verbs: [migrate] }
  migrate: { do: "flyway migrate" }
```

All three can change behavior completely; they differ in what they say. Directory says "a separate unit with its own files", platform "the same operation, elsewhere", vocabulary "a different operation". A database migration can be `sayt --directory db build`, `sayt build@postgres` or `sayt migrate`; the last usually says it best. When a platform beats a flag is in the **sayt-tdd** skill.

## Per-Verb Skill Reference

For detailed guidance on writing the configuration file for each verb, see the per-verb skills: `sayt-cli`, `sayt-ide`, `sayt-code`, `sayt-cnt`, `sayt-k8s`. For a compact verb → tool → config card and troubleshooting by verb, see [reference.md](./reference.md).

## Current sayt help

Run `sayt help` for current flags and options.
