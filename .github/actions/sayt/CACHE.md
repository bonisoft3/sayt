# sayt CI actions — the build-cache contract

The four composite actions form a ladder of increasing power and setup cost.
Their **cache stance** is the dividing line, and it follows one rule: *the
lower an action sits, the more it assumes about the cache; the higher it sits,
the more it delegates to the build graph.*

| action | cache stance |
|---|---|
| `sayt/install` | n/a — no builds, only the saytw + mise binary cache |
| `sayt/integrate` | **assumes no cache config exists** — wires (and overwrites) cache itself |
| `sayt/ci` | **always delegates to the graph's `x-bake`** (bayt-optional) |
| `sayt/depot` | **assumes bayt is mandatory** |

## sayt/integrate — owns the cache

The standalone, non-bayt path. The project's `compose.yaml` is assumed to carry
**no** `x-bake.cache-*`, so the action wires caching itself:

- `cache-scope` set → injects `type=gha` per-scope + `main` fallback on
  `cache-from`, `mode=max` on `cache-to`.
- `cache-from` / `cache-to` set explicitly → those win verbatim (e.g. a
  `type=registry` ref for projects whose layer set overflows GHA's ~10 GB).

It is fine — by design — for `sayt/integrate` to overwrite. It is not trying to
collaborate with a graph that declares its own cache.

## sayt/ci — always delegates

`sayt/ci` runs in bake mode: the `ci` bake target's RUN body orchestrates the
inner `docker compose up integrate` against the bind-mounted host daemon. It
**always delegates** caching to the graph — it injects no cache `--set` of its
own. Whatever the compose declares in `x-bake.cache-{from,to}` drives caching;
the action only transports the scope (`CACHE_SCOPE`, interpolated into the
graph's refs) and the `SAYT_NO_CACHE` / `SAYT_NO_CACHE_TO` kill switches.

bayt is **not** mandatory here: the `x-bake.cache-*` refs can be bayt-generated
(per-target recipes) or hand-written. There is deliberately no action-level
cache override — a project that wants different caching edits its own `x-bake`.
(If a non-bayt consumer ever needs the action to impose cache without an
`x-bake`, the seam would be a `cache-from`/`cache-to` passthrough threaded
through `integrate.nu` into `--set`, mirroring `SAYT_NO_CACHE_TO` — but nothing
needs it today.)

## sayt/depot — bayt mandatory

The three-phase warmup/outer/inner flow, the registry-mediated image
distribution, and the declared `CACHE_SCOPE` (branch + depot project + frontend
pin) all assume bayt's emission — per-target `x-bake` refs, the dindbox inject
body, the `bayt_image_ns` / `cache_scope` secrets. There is no non-bayt depot
path.

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
