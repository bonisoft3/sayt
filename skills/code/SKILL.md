---
name: sayt-code
description: >
  How to write .say.cue / .say.yaml — the ordered-map rule pattern,
  built-in generators (auto-gomplate, auto-cue), declarative lint sugar
  (copy, shared, vet), CUE basics.
  Use when setting up code generation or lint rules.
user-invocable: false
---

# generate / lint — `.say.{cue,yaml,nu}` Configuration

`sayt generate` runs code-generation rules. `sayt lint` runs static checks. Both are driven by configuration in `.say.{cue,yaml,yml,json,toml,nu}` files merged with sayt's built-in `config.cue`.

`.say.nu` files are executed and their output is piped into the CUE evaluator. All other files are `cue export`-merged directly.

## Rule Shape

Rules are defined via an ordered map (`rulemap`) that flattens to a list. Each rule has a list of `cmds`, each of which is a nushell command block:

```yaml
say:
  generate:
    rulemap:
      my-rule:
        cmds:
          - do: "buf generate"         # nushell expression run inside `do { ... }`
            use: "./module.nu"         # optional: nushell module to import first
            workdir: "./gen"           # optional
            inputs:  ["../proto/"]     # optional: files the rule depends on
            outputs: ["gen/"]          # optional: files the rule produces
```

### The Ordered Map Pattern

Keys enable granular composition:

- **Add**: introduce a new unique key.
- **Modify**: reference an existing key to merge fields.
- **Delete**: set an existing key to `null`.
- **Order**: optional `priority` field; stable by name within priority.

```yaml
say:
  generate:
    rulemap:
      "auto-cue": null          # disable a built-in
      my-protobuf:              # add a custom rule
        priority: 10
        cmds:
          - do: "buf generate"
```

## Built-in Generate Rules

sayt ships two built-in generate rules, both enabled by default:

### `auto-gomplate`

Implemented in `generate-gomplate.nu`. For every `X.tmpl` in the current directory, runs `cue export X.cue` to produce JSON data, then pipes it into `gomplate -d data=stdin:///data.json -f X.tmpl`, saving the result as `X`.

Convention:
```
Dockerfile.tmpl + Dockerfile.cue → Dockerfile
```

### `auto-cue`

Implemented in `generate-cue.nu`. For every `X.cue` whose stem `X` is an existing file, runs `cue export X.cue --out <ext>` and saves the result as `X`.

Convention:
```
compose.cue (if compose.yaml exists) → compose.yaml
```

Disable a built-in with `rulemap: { "auto-gomplate": null }` or `{ "auto-cue": null }`.

## Built-in Lint Sugar

sayt's built-in lint verb runs `auto-cue.nu`, which performs three kinds of checks declared at the top level of `say.lint`:

### `copy` — files that must be byte-identical

```yaml
say:
  lint:
    copy: ["libraries/foo/README.md", "services/bar/README.md"]
    # or a list of lists for multiple groups
    copies:
      - ["a.json", "b.json"]
      - ["Dockerfile", "Dockerfile.alt"]
```

Each group lists 2+ files. The first file is canonical; the others must match byte-for-byte or lint fails with a `cp` hint.

### `shared` — regex-extracted values that must agree

```yaml
say:
  lint:
    shared:
      pattern: 'version = "(\d+\.\d+\.\d+)"'
      files: ["Cargo.toml", "pyproject.toml", "package.json"]
```

The regex is extracted from every file. Missing matches fail; differing captured values fail with a side-by-side diff.

### `vet` — `cue vet` for CUE-generated files

For every `X.cue` whose stem `X` is an existing file, runs `cue vet X.cue <ext>:X` to confirm the generated file still satisfies the CUE schema. This is the static counterpart to `auto-cue` generate.

All three checks run as the single built-in `auto-cue` lint rule. Disable with `rulemap: { "auto-cue": null }`.

### Type Annotations for Custom Lint Rules

For rulemap entries, sayt exposes `#copy`, `#shared`, and `#vet` type annotations that let you attach a declarative check to a named rule instead of using the top-level sugar:

```cue
package say
say: lint: rulemap: {
  "version-pins": #shared & { shared: { pattern: "v[0-9]+\\.[0-9]+\\.[0-9]+", files: [...] } }
}
```

## Adding Custom Rules

### Generate — protobuf example

```yaml
say:
  generate:
    rulemap:
      protobuf:
        cmds:
          - do: "buf generate ../../libraries/xproto"
            outputs: ["gen/"]
```

### Lint — run app linters and config validators

The broader `lint` verb is where app linters and config validators live. Use `mise exec --` for any mise-managed tool invocation:

```yaml
say:
  lint:
    rulemap:
      app:
        cmds:
          - do: |
              mise exec -- pnpm lint
              mise exec -- pnpm exec tsc --noEmit
      configs:
        cmds:
          - do: |
              mise exec -- rpk connect lint services/transform/pipelines/*.yaml
              mise exec -- caddy validate --config services/proxy/Caddyfile --adapter caddyfile
              mise exec -- kubeconform -summary -strict k8s/base/*.yaml
```

See the `sayt-tdd` skill for why `lint` is the right verb for all static checks.

## `.say.cue` — Typed Rules in CUE

```cue
package say

say: generate: rulemap: "openapi-types": {
  cmds: [{
    do:      "openapi-typescript api.yaml -o types.ts"
    inputs:  ["api.yaml"]
    outputs: ["types.ts"]
  }]
}
```

CUE unifies rather than overwrites, so you can split rules across multiple `.say.cue` files and they merge automatically. Defaults use `*value | type`. Use `null` to delete.

## `.say.nu` — Dynamic Rules

For configuration that needs runtime logic, write a nushell file that outputs YAML/JSON. Its output is merged with the other `.say.*` files:

```nushell
# .say.nu
{
  say: generate: rulemap: {
    dynamic: {
      cmds: [{ do: $"echo (date now | format date '%Y')" }]
    }
  }
} | to yaml
```

## `--force`

`sayt generate --force` sets `SAY_GENERATE_ARGS_FORCE=true`. Built-in rules honor it via `save --force=$env.SAY_GENERATE_ARGS_FORCE`. Custom rules that write files should do the same.

## Current flags

Run `sayt help generate` and `sayt help lint` for current flags.
