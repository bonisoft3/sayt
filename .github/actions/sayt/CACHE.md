# sayt CI actions — the build-cache contract

The four composite actions form a ladder of increasing power and setup cost.
Their **cache stance** is the dividing line, and it follows one rule: *the
lower an action sits, the more it assumes about the cache; the higher it sits,
the more it delegates to the build graph.*

| action | cache stance |
|---|---|
| `sayt/install` | n/a — no builds, only the saytw + mise binary cache |
| `sayt/integrate` | **assumes no cache config exists** — wires (and overwrites) cache itself |
| `sayt/ci` | **delegates the refs to the graph's `x-bake`**, owns on/off (bayt-optional) |
| `sayt/depot` | **assumes bayt is mandatory** |

## sayt/integrate — owns the cache

The standalone, non-bayt path. The project's `compose.yaml` is assumed to carry
**no** `x-bake.cache-*`, so the action wires caching itself:

- `action-cache-scope` set → injects `type=gha` per-scope + `main` fallback
  on the import, `mode=max` on the export.
- `action-cache-from` / `action-cache-to` set explicitly → those win verbatim
  (e.g. a `type=registry` ref for projects whose layer set overflows GHA's
  ~10 GB).

`sayt/integrate` has no bake-mode on/off switches of its own — those live on
`sayt/ci`, which forwards them as `sayt integrate` flags (see below).

It is fine — by design — for `sayt/integrate` to overwrite. It is not trying to
collaborate with a graph that declares its own cache.

## sayt/ci — delegates the refs, owns on/off

`sayt/ci` runs in bake mode: the `ci` bake target's RUN body orchestrates the
inner `docker compose up integrate` against the bind-mounted host daemon. The
graph owns *which* refs — whatever the compose declares in
`x-bake.cache-{from,to}` — and the action transports the scope (`CACHE_SCOPE`,
interpolated into those refs).

What the action does own is **whether** they apply: `cache-from` / `cache-to`
are on/off switches, `true` or stripped, gated independently so trunk can
export while branches import for free. Strict bools — a `yes` or a generated
`True` is refused rather than read as `false`, which would strip a tier in
silence; empty is an unset input threaded in and lands on the default. They reach both the outer bake and the
inner via `sayt integrate --no-cache-{from,to}`. The refs themselves stay the
graph's business — a project that wants *different* caching edits its `x-bake`.

bayt is **not** mandatory here: the `x-bake.cache-*` refs can be bayt-generated
(per-target recipes) or hand-written.

## sayt/depot — bayt mandatory

The three-phase warmup/outer/inner flow, the registry-mediated image
distribution, and the declared `CACHE_SCOPE` (branch + depot project + frontend
pin) all assume bayt's emission — per-target `x-bake` refs, the dindbox inject
body, the `bayt_image_ns` / `cache_scope` secrets. There is no non-bayt depot
path.

`cache-from` / `cache-to` gate only the registry tier; the builder's own cache
sits underneath and answers to `no-cache` on `phase: build`, whose input says
when that is the right lever.

## Cross-cutting: cache semantics

Two CAS caches with different write behavior, which dictates discipline:

| | `type=gha` / `type=registry` ref | depot native cache |
|---|---|---|
| write | **overrides** the scope/ref slot (last-writer-wins) | **additive** (accumulates, GC-evicts) |
| consequence | scope carefully (pr vs main), read with fallback, never write in phase-2 | many writers safely merge → warmup-as-single-writer + read-only shards (`no-cache-to`) |

Moving a project from `type=gha` to a `type=registry` ref lifts the ~10 GB GHA
cap and gives backend control, but keeps **override** semantics — it is not the
override→additive jump (that is depot's alone).

## Cross-cutting: cache mode (min vs max)

For a **monolithic** multi-stage build, `mode=max` is needed to cache the
intermediate stages that never reach the final image.

For a **bayt** graph, every stage is its own single-output target with its own
`cache-to`, so each target's `mode=min` fully caches its leaf, and the union of
per-target `min` exports equals what `mode=max` would cover on a monolith — with
fewer layer descriptors, fewer registry existence (HEAD) round-trips, and
smaller/faster manifests. So: match the mode to how the graph is built —
decomposed DAG → per-target `min`; hand-written monolith → `max`. The only thing
`min` misses is an expensive throwaway stage *inside* a single target's
Dockerfile; in bayt the fix is to make that stage a target, not to reach for
`max`.

Both of bayt's backend recipes (`core/bayt.cue`) emit `mode=min` for this
reason — `registry` and `gha` alike. The standalone `sayt/integrate` GHA
default stays `mode=max`, which is correct there: it serves non-bayt projects
whose single multi-stage target is not decomposed.
