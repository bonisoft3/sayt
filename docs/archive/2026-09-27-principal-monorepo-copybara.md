---
type: decision
title: Product glue directories and copybara mirrors
description: A product is a thin directory that composes per-service sayt configuration, and every public repository is a copybara view of the monorepo.
status: done
moved_to: ../../README.md#principal
---

# Product glue directories and copybara mirrors

## Context

A product is a frontend, a backend on a database and a few stateless or
event-driven services, in different languages and at different levels of
quality. Sayt's per-directory configuration solves each service on its own; the
open question is how they become one product, and how parts of it reach public
repositories.

## Decision

Each service is a directory with its own `.vscode/tasks.json`, `.mise.toml`,
`Dockerfile` and `compose.yaml`, and nothing about it changes when the product
forms. The product is a glue directory that references the services without
duplicating their configuration:

```
monorepo/
  services/api/           # sayt build/test here
  guis/web/               # sayt build/test here
  products/todoapp/       # sayt launch/integrate here
    skaffold.yaml         # requires: ../../services/api/skaffold.yaml, ...
    compose.yaml
    overlays/{preview,production}/
```

The glue describes how the services meet once deployed — networking, shared
databases, environment overlays — and no application logic. `sayt launch` there
brings the stack up, `sayt integrate` runs the end-to-end tests against it, and
service teams keep their fast `build`/`test` loop in their own directories.

Parts that must be public — a tool, a client SDK, the product itself — are
copybara views. A `copy.bara.sky` at the root declares one workflow per
published subset; `core.move` rewrites paths so the subset looks like a
standalone root, `ITERATIVE` replays every commit for a plugin, `SQUASH`
collapses history for a product. Copybara rides the `release` verb, so
publishing a subset is the same act as releasing it.

Sayt itself is published this way: the `sayt` workflow moves `plugins/sayt` to
the root of `bonisoft3/sayt`, pins its composite-action references to
`bonisoft3/sayt/...@<VERSION>`, stages `.mirror/cue.mod/module.cue` as
`cue.mod/module.cue` and rewrites `bonisoft.org/plugins/sayt` imports to
`github.com/bonisoft3/sayt`. Relocatability — every path relative, no
repo-level roots — is what lets one `core.move` do the job.

## Alternatives

- **Separate repositories composed with submodules.** The same layout works
  with the product as the superproject, but a change that crosses two services
  is two commits and two reviews. Atomic cross-service changes are the reason
  to keep one repository and derive the public ones.
- **A product directory that owns the build.** Repeating the services' build
  definitions in the glue drifts as soon as one changes; `requires` keeps each
  definition where its owners edit it.
- **Publishing the monorepo itself.** Consumers of a plugin need a standalone
  root (a `cue.mod`, an import path, an action reference on a tagged commit),
  and a public monorepo exposes everything that is not the plugin.
