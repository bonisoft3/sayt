# Design: enveloped build/run phases for sayt/depot

Status: proposal. Author: design discussion, 2026-06.

## Where we are (post #1391)

The separate host **warmup** is gone. `sayt/depot` now = set up the depot buildx
instance + run `sayt/ci` on it. The `ci` target's `cmd.builtin.do` RUN
(`bake <target>` + `compose up <target>`, `plugins/bayt/stacks/sayt/sayt.cue:254-255`)
is the only work, and it gets skip-on-full-hit **for free**: it's the RUN body of
the outer `ci` bake target, so unchanged source inputs → that RUN layer is `CACHED`
→ the inner bake and the up never re-execute.

> The skip is the outer bake RUN-layer cache hit — NOT the marker.
> The marker (`integrate/action.yml`, `mode == 'compose'`) is the compose-mode
> substitute for the same skip, needed only because a `compose up` *action step*
> isn't layer-cached. The `--bake`/RUN envelope gets it from buildkit.

## Problem this design solves

The inner **bakes + loads** the whole graph (`output: type=docker`, ~66
`exporting/importing to docker` ops) rather than **pulling** prebuilt images. That's
fine for a self-contained service (tracker: one in-process integrate, nothing to
pull) — but wrong for a service whose run phase composes up a **built launch stack**.
That service wants: build the stack once (cheap runner, depot does the work, push),
then pull + run it (bigger runner). The lever is splitting the single `build+run`
RUN into two **enveloped** phases — each still a cacheable RUN, each skip-on-hit.

The in-repo service with that shape is **`guis/iris`**, not tracker (see below).

## Goal

One enveloped dindbox cmd template, parameterized by `build:` / `run:`, used for
every phase. Each phase is a RUN inside an outer bake target → all get the same
free skip-on-full-hit; no marker to build.

| `build:` | `run:` | RUN body | bake output | phase |
|---|---|---|---|---|
| ✓ | ✗ | `bake <target>` | `type=registry` (push) | warmup |
| ✗ | ✓ | `compose up <target>` (no `--build`) | — (`up` pulls via `pull_policy: missing`) | shard |
| ✓ | ✓ | `bake <target>` ; `compose up <target>` | `type=docker` (load) | dev / local |
| ✗ | ✗ | (noop) | — | — |

Output is **derived from the pair**, not a third flag. Both flags default `true`
(dev behavior unchanged). Push uses a per-target override (`--set
"<target>.output=type=registry"`), never `*` (that hits local-only `_srcs`).

## How the depot action calls it

For a pull-shaped consumer (iris), the action runs **two enveloped bakes** on the
depot builder instead of one `sayt/ci`:

- build phase → bake the **build-only** target (`run:false`): builds + pushes the
  launch stack. Skips on full hit.
- run phase → bake the **run-only** target (`build:false`): pulls + runs. Skips on
  full hit.

On a fresh commit both run (build pushes, run pulls). On a source-unchanged re-run
both RUN layers hit → both skip. A self-contained consumer (tracker) keeps the single
`build:true/run:true` call — no second phase.

## Caching: distinct bodies already give distinct keys

No special effort. Because the flags are generation-time, each phase emits a
different RUN body, so the outer-bake RUN-layer cache keys are distinct by
construction:

- warmup: `bake <t> --output=type=registry` (no up)
- shard:  `compose up <t>` (no bake)
- dev:    `bake <t> --output=type=docker` ; `compose up <t>`

All three differ → none can cache-hit another. The shard's `up` is still a RUN, so
it skips on its own key (the COPY'd source tree). The inner `integrate` *build*
cache is shared across dev/warmup via the depot cache — output type (`load` vs
`push`) is applied after the build and isn't part of the build key — which is
desirable.

The only way a collision arises is the path we are NOT taking: one shared target
with `build:`/`run:` as runtime *env* (secret-env, not in the cache key) → identical
RUN text → the shard hits the warmup's layer. Generation-time flags (distinct
bodies) avoid it — that's the reason to prefer them over runtime env, not a separate
decision.

## Target: `guis/iris` (the pull-shaped service)

iris is the only in-repo service whose run phase pulls a built stack. Its
`integrate` is a Playwright e2e that `compose up`s a multi-service graph (its
`depends_on`, `guis/iris/bayt.cue:224-230`):

```
launch (the app), caddy, conduit, transform, rclone-s3, imgproxy
  (+ crud / database / electric / redis per the header)
```

~10 **built** images the run phase brings up — exactly where build-once/pull-many
pays off, and where the run (a browser) wants a bigger machine than the build. It's
also the natural place to shard (`playwright e2e + integration suites`,
`guis/iris/bayt.cue:109-111`): N shards pull the **same** prebuilt stack.

iris is already on the same depot project (`registry.depot.dev/f5k5087x1b`,
`iris-bake-cache-v13`) but does **not** use `sayt/depot` yet — adoption is the work.

Phases for iris:

- **build** (`run:false`, small runner): `bake` the launch stack → `output=type=registry`,
  push every service image under `<org>.registry.depot.dev/...:$SHA`.
- **run** (`build:false`, big runner, ×shards): `compose up integrate` → `pull_policy:
  missing` pulls the pushed stack, runs the e2e suite. No bake, no 66-load.

tracker stays single-phase `build:true/run:true` (no push) — #1391.

## Relationship to `--bake` (integrate.nu)

Different levels — keep the names distinct:

- `--bake` selects the **envelope**: run the cascade as a `docker buildx bake` whose
  target RUN body executes the test (exit code = verdict), vs the default plain
  `docker compose up <target>`.
- `build:` / `run:` choose **which lines run inside** that enveloped `cmd.do`.

"`--bake` with `build:false`" must not read as a contradiction — hence `build:`/`run:`
for the inner lines, not `bake:`.

## Robustness caveat

The RUN-layer cache and the registry image lifetime are decoupled. A
source-unchanged re-run cache-hits the warmup RUN and skips re-pushing — correct
only while the pushed image still exists. If depot GC'd it (past retention) but the
build cache survived, the shard's pull misses. Rare (similar lifetimes); only
worth a verify-or-repush guard if it actually bites.

## Open decisions / next

1. **Move `guis/iris` onto `sayt/depot`** first (it isn't yet) — establishes the
   pull-shaped consumer the split exists for.
2. Add `build:`/`run:` to `cmd.builtin` (generation-time, default both true). Keep
   the both-true `do` **byte-identical** to today's so no project's RUN-layer cache
   busts (the `do` text is part of the key).
3. Wire the depot action to bake iris's build phase (`run:false`, push) then the run
   phase (`build:false`, pull) — sharded on the run side.
4. Measure on iris: build+load-the-stack vs build-once/pull. tracker stays
   single-phase `build:true/run:true` (#1391); it is not the measurement target.
