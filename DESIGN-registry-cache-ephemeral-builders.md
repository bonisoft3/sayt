# sayt/bayt: registry cache for ephemeral builders + reproducible layers

Spec for upstream (bonisoft3/sayt + bayt). Reasoning-first so you can weigh the
options across all sayt clients. No downstream specifics — the shapes below (a
federated multi-stage build closure with a compile chain and an mtime-clamp) are
generic to any sayt project that bakes on remote/ephemeral builders.

## Problem: cache never warms on CI

`sayt/depot` phase:build runs a flat `depot bake` and **strips the bake's registry
cache**: `--set "*.cache-from=" --set "*.cache-to="` (and the dindbox path sets
`SAYT_NO_CACHE_FROM/TO=1`). The comment says "depot's builder-native cache
suffices."

That holds only for a **stable, single builder**. It fails on every **ephemeral
or autoscaled builder pool**:

- **depot autoscaling**: builds route to a single builder per arch *by default*,
  but under concurrency depot spins additional builders "on a **clone** of the
  main builder's layer cache **that is not written back**" (depot's own docs). So
  a build hits the warm cache only if it re-lands the *same* machine. Under CI
  concurrency (the bake fans out, run/flow shards run in parallel, multiple PRs
  share the project) that essentially never happens.
- **`sayt/ci`** (local buildx on CI runners): every CI run is a **fresh ephemeral
  runner**, so the local buildx cache is empty each run — same failure, different
  mechanism.

Measured on a large closure **with depot autoscaling on**: warm build ≈ cold
build (no cross-build reuse), i.e. **zero cache hits across CI builds**, despite
a "persistent cache" existing. Autoscaled, the builder-native cache is a lottery
CI does not win.

## Fix part 1 — stop stripping the registry cache (why it works)

The bake **already generates** per-node `mode=min` registry cache-from/to (the
federated design: each stage is its own bake target with its own cache tag). It is
simply being stripped. Registry cache (`type=registry`) is **builder-independent**
— content-addressed, stored in the registry, importable by *any* builder or
runner. (Verified directly: a cache written from one builder is imported and hit
by 4 *different* builders; a builder-native cache is only hit by the same
machine.)

So un-stripping cache-from makes reuse survive across machines/runners, which is
exactly what the ephemeral pools break.

## Fix part 2 — reproducible layers via `rewrite-timestamp` (why it's also needed)

With the registry cache un-stripped, most nodes hit — but the **compile chain**
(setup → build) still re-runs. Root cause is the **mtime-clamp**:

- The clamp (`find <workdir> -exec touch -hd @0 {} +`) re-runs **every build**: its
  input is a COPY whose synthetically-created parent directories carry build-time
  mtimes that float run-to-run. So the clamp step *misses and re-executes*, and its
  **computed chain-key floats**.
- That float **propagates down the chain** (setup → build): those nodes miss the
  registry import, re-run, and the re-run regenerates layers with fresh build-time
  mtimes → drift. On a single persistent builder this is masked (buildkit content-
  matches the re-run output locally); across builders via registry it is not.

`rewrite-timestamp=true` on the **pushed images** normalizes exported layer mtimes
to `SOURCE_DATE_EPOCH` → ancestor images become **byte-reproducible across builds**
→ buildkit's **content-digest** matching recovers the hit even though the chain-key
floated → the compile chain finally caches.

Measured (heavy recompiles on a warm read of a large closure):
`mode=min alone: 75` → `+mode=max: 56` (a red herring — see below) →
`+rewrite-timestamp: 0`.

**But the mechanism above is unconfirmed.** Two later measurements cut against it:

- It does **not** normalize the registry *cache* export. Two `--no-cache` builds
  with `--output type=oci` + `--cache-to type=local,mode=min`: the image layer
  goes `4ec47e532ecc`→`cab865be484b` without it and `ff0e3f210780`→`ff0e3f210780`
  with it, while the cache-export blob sets stay disjoint either way. It is an
  image-exporter attribute; the cache exporter references the original layers.
- A reduced `src → COPY → clamp(touch @0) → COPY → compile` chain, cache
  exported `mode=min`, builder pruned, upstream forced to re-run with fresh
  mtimes: the clamp RUN re-executed as described, but `compile` still came back
  **CACHED** — content-matched, with no rewrite-timestamp anywhere.

So something in the real closure carries a float the clamp does not normalize,
and the `0` above may be incidental. Re-measure before treating this as the
load-bearing fix. It is applied to the depot push regardless: reproducible
pushed layers are worth having on their own.

Scope of rewrite-timestamp:
- **Needed** on nodes whose RUN steps create build-time-mtime files that feed a
  cross-build cache consumer: setup (toolchain/deps install), build (compile),
  launch (data seeding).
- **Not** needed on the clamp stages themselves — they self-normalize (touch @0).
- Blanket-on-every-pushed-image is cheap and safe; narrowing to the build chain
  saves ~nothing on wall time (the wall is dominated by the image push, below).

### Why NOT mode=max

`mode=max` was tested and is the **wrong lever**: it caches more intermediates
(faster overall) but does **not** fix the compile (the chain-key float is mode-
independent). It also has a cost on a federated graph: `mode=max` on a target
exports its whole transitive stage graph, so shared COPY-`--from` ancestors get
re-referenced by every descendant. Storage does **not** duplicate (content-
addressed — verified: max ≈ min distinct blob count), but each descendant does
per-ancestor manifest/existence-check **ops** on export and import. buildkit has no
"max minus external contexts" mode. The federated `mode=min` design already caches
each stage once; keep it.

## Fix part 3 — write-on-trunk (cache-to gating), why

Cache **export (write)** has a real cost (measured ~20% of a warm build). Cache
**import (read)** is cheap. So: **write cache only on the trunk branch**; feature
/ PR builds are **read-only** (import trunk's cache via a scope fallback). This
requires `cache-from` and `cache-to` to be **independently** controllable, and the
cache scope to be branch-aware with a trunk fallback.

One builder needs none of this — its native cache is already warm. This repo
runs one today and still opts in, so a builder wipe has something to recover
from and the switch is already flipped when autoscaling arrives.

## Fix part 4 — env-gate rewrite-timestamp (don't tax local dev)

`rewrite-timestamp` is an **exporter** attribute — it fires on *any* materialize,
including `type=docker` (local dev load), not just registry push. Applying it
unconditionally taxes every local build. Gate it to registry pushes.

## Concrete changes

**bayt: none.** `mode=min` stays, and the exporter needs no new hook — the
existing `type=${BAYT_COMPOSE_OUTPUT:-docker}` is a raw interpolation, so a
pusher sets `BAYT_COMPOSE_OUTPUT=registry,rewrite-timestamp=true` and a local
load leaves it `docker`. `SOURCE_DATE_EPOCH=0` keeps being passed
(rewrite-timestamp needs it).

**`sayt/depot` and `sayt/ci`** both wrap the bake and share the problem:

- Independent `cache-from` / `cache-to` on/off switches replacing the
  hardcoded strip, forwarded down the wrapper chain to `sayt integrate
  --no-cache-{from,to}` so one switch means one thing on every bake a run
  drives. On by default in `sayt/ci`, whose runners are always cold; opt-in in
  `sayt/depot`, whose builders keep a native cache worth trying first.
- `CACHE_SCOPE` + `CACHE_SCOPE_FALLBACK` on the **build** path too — lift
  `sayt/depot`'s scope compute out of its `phase != build` gate. `sayt/ci`
  already gets a branch-aware scope from `dind.nu`.
- `BAYT_COMPOSE_OUTPUT=registry,rewrite-timestamp=true` where we push.
- Scope producers owe bayt one thing: `len(CACHE_SCOPE) <= 64`, which
  `#cacheTagSeg` assumes when it budgets per-target segments as
  `62 - len(<project scope>)`. There are two producers — `dind.nu` for the
  local/dindbox path, and inline bash in `sayt/depot`, which computes the
  scope before any toolchain exists (installing sayt to reach nushell would
  cost ~5.5s against a fully-warm bake-only job of ~10s — the very case this
  change exists to make fast). They feed **disjoint** namespaces (the engine
  dimension differs), so their strings need not match; only the bound is
  shared, and each bounds the *composed* scope rather than each dimension, so
  an unbounded input cannot overflow. `dind_test.nu` holds the nushell one to
  it.

`sayt/ci` matters as much as `sayt/depot`: its runner-local cache has the **same
ephemerality**. Note its bakes are `type=cacheonly`, so rewrite-timestamp has
nothing to attach to there — it gains the registry cache, not reproducible
layers.

## Deferred (separate from this change)

Warm-build wall time on a large closure decomposes as roughly: image-push of the
runtime closure (largest), registry cache import, and fixed job overhead
(checkout, toolchain install) — with **zero compute**. So after this change the
remaining levers are:
- **Fingerprint-gate the image push** — skip re-pushing runtime images whose
  content is unchanged (most, on a warm build); consumers pull the existing ones.
  This is the single biggest remaining warm cost.
- **Coarser cache federation** (fewer, fatter tags) to cut import round-trips.
- Toolchain-install caching. **Checkout depth is already spent**: every CI job
  is on `actions/checkout`'s shallow default, and the `fetch-depth: 0` uses left
  are all release/mirror jobs that need real history (`copybara-sync`,
  `cd.yml::propagate-tag`'s target checkout, the sayt and boxer release jobs).
  There is also no git-mtime source to trade against — nothing in sayt or bayt
  derives mtimes from commit times; the `Pin mtimes` clamp in `sayt/integrate`
  is the only normalizer, and it is depth-independent. No submodules, and no
  tag-dependent tooling on the hot path.
