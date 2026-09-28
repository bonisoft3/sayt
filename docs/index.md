# sayt

# Entry points

* [sayt](../README.md) - concept: What sayt is, how to install it, and how a project configures its ten verbs.
* [Contributing to sayt](../CONTRIBUTING.md) - howto: The file map of plugins/sayt, how to run its tests, and the loop for changing it.
* [sayt-lifecycle](../skills/sayt/SKILL.md) - reference: Unified development lifecycle tool. Use when the user asks about building, testing, setting up, deploying, or configuring a development environment. Teaches how to write and fix the configuration files behind each verb and how to configure sayt itself.
* [sayt Quick Reference](../skills/sayt/reference.md) - reference: Verb → tool → config → command for the ten verbs, the integrate build axes and capability flags, and troubleshooting by verb.
* [sayt-tdd](../skills/tdd/SKILL.md) - reference: The TDD loop for sayt projects. Use when implementing features, fixing bugs, or diagnosing failures. Teaches how to pick the verb pair that gives fastest feedback at the current layer, ping-pong inside that layer until green, then advance the cascade.
* [sayt-cli](../skills/cli/SKILL.md) - reference: How to write .mise.toml + mise.lock for sayt setup / doctor — tool versions, the http: backend, lockfile auditing across platforms, and mise exec for non-shim invocations. Use when setting up project toolchains or fixing missing tools.
* [sayt-code](../skills/code/SKILL.md) - reference: How to write .say.cue / .say.yaml — the ordered-map rule pattern, built-in generators (auto-gomplate, auto-cue, auto-bayt), declarative lint sugar (copy, shared, vet), CUE basics. Use when setting up code generation or lint rules.
* [sayt-ide](../skills/ide/SKILL.md) - reference: How to write .vscode/tasks.json for sayt build / test — task schema, dependsOn chains, Windows overrides, and canonical per-language patterns. Use when creating build tasks, test tasks, or fixing compilation failures.
* [sayt-cnt](../skills/cnt/SKILL.md) - reference: How to write Dockerfile + compose.yaml for sayt launch / integrate — the service convention, multi-stage targets, multi-platform sha256 pinning, dind helpers. Use when containerizing a project or writing integration tests in containers.
* [sayt-k8s](../skills/k8s/SKILL.md) - reference: How to write .goreleaser.yaml + skaffold.yaml for sayt release / verify — the monorepo pattern where goreleaser delegates image publishing to skaffold build --push, plus direct skaffold usage for deploys. Use when wiring release pipelines or preview/staging/production deploys.
* [sayt-dev-loop](../agents/dev-loop.md) - reference: Full-lifecycle development agent that drives the sayt TDD loop. Use proactively when implementing features, fixing bugs, or setting up projects. Picks the verb pair that iterates fastest at the current layer, ping-pongs until green, then advances the cascade.
* [sayt CI actions — the build-cache contract](../.github/actions/sayt/CACHE.md) - reference: Which of the composite actions owns the build cache and which delegates it to the graph's x-bake refs, and why the cache mode follows how the graph is built.

# Archive

* [Enveloped build/run phases for sayt/depot](archive/2026-06-23-depot-build-run-phases.md) - decision, done: Splits the depot cascade into a build phase that pushes the stack and a run phase that pulls it.
* [sayt:loop package](archive/2026-07-30-loop-first-class.md) - decision, done: sayt publishes its development-lifecycle contract as the CUE package `sayt:loop`, which pronto rosters as `pronto/loops:sayt`.
* [Product glue directories and copybara mirrors](archive/2026-09-27-principal-monorepo-copybara.md) - decision, done: A product is a thin directory that composes per-service sayt configuration, and every public repository is a copybara view of the monorepo.
