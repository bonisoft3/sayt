# sayt/depot: `push-images` warmup produces two outputs per push target

Severity: blocks pull-mode (`bake: images: pull`) adoption via the composite.
Found by the first external pull-mode consumer, 2026-06-12 (their run
27444466238); consumer-side workaround validated the fix shape.

## Symptom

With `push-images: "true"`, the warmup bake fails immediately:

```
ERROR: multiple outputs currently unsupported by the current BuildKit daemon,
please upgrade to version v0.13+ or use a single output
```

against depot's builder (`v0.13.2-depot.26`).

## Root cause

The warmup step (`.github/actions/sayt/depot/action.yml`) composes, for each
requested push target:

```
--set "*.output=type=cacheonly"            # wildcard, whole graph
--set "<target>.output=type=registry"      # named, per push target
```

The step comment claims "a named --set beats the wildcard". That is wrong for
`output`: buildx **appends** when multiple `--set` flags hit the same field of
one target — each push target ends up with an output LIST of two entries
(`cacheonly` + `registry`), and the daemon capability gate rejects it.

Reproducible without depot, in seconds, via `--print`:

```sh
docker compose config | docker buildx bake -f - --print \
  --set "*.output=type=cacheonly" \
  --set "sometarget.output=type=registry" \
  sometarget | jq '.target.sometarget.output | length'
# => 2   (bug: expected 1)
```

That `--print` assertion is also the regression test.

## Fix: two-phase warmup (recommended)

Keep phase 1 exactly as today; add a push phase that never mixes outputs:

1. **Phase 1 (unchanged, always):** `--set "*.output=type=cacheonly"` over
   `warmup-target` — warms depot's native cache + writes registry cache refs
   across the full graph. Single output everywhere, works on every builder.
2. **Phase 2 (only when `push-images == 'true'`):** a second bake of ONLY the
   push targets with per-target `--set "<t>.output=type=registry"` and **no
   wildcard at all**. Requested targets carry exactly one output; their deps
   build inline with none. Phase 1 makes this a pure cache-hit walk — the
   phase costs only export + push (builder-side egress).

Notes:
- The `BUILDKIT_SYNTAX` wildcard arg `--set "*.args.BUILDKIT_SYNTAX=…"`
  composes fine with named output sets (args merge by key; no output-list
  interaction) — keep it on both phases.
- Fix the misleading "named beats wildcard" comment while there.
- If a separate push set is ever wanted (push fewer targets than you warm),
  phase 2 naturally takes its own target list; today reuse `warmup-target`.

### Alternative considered (what the consumer's workaround does)

Single-phase: when pushing, drop the cacheonly wildcard entirely and request
only the push targets with per-target registry sets. Equivalent for the
launch-image set (deps warm as inline builds), but it changes the no-push
path's shape and loses the ability to warm a broader graph than you push —
two-phase preserves existing behavior exactly and isolates the new code to a
conditional step.

## Acceptance

- `bake --print` assertion above returns 1 output per push target.
- hello canary (ttl.sh tier) green with `push-images: "true"`.
- Consumer flips `push-images` back on and deletes their workaround step
  (their workflow documents the flip-back inline).

## Second gap found by the same consumer (run 27445104230): x-bake `tags` push

With the outputs bug bypassed, `output=type=registry` pushes **every**
name on the target — including bayt-emitted x-bake `tags:` aliases
(e.g. `it-celcoin:latest`), which resolve to docker.io → push denied.
Those aliases exist to bridge bayt-built images to legacy harness
composes under the type=docker load flow.

Upstream fix candidates (bayt side, pull mode):
- suppress `tags:` emission when `images: pull` is on (the aliases are
  meaningless without a local load), AND/OR
- the push phase clears them per target (`--set "<t>.tags="` — empty
  --set verifiably clears array fields on buildx >= 0.30), and
- if consumers need the aliases daemon-side, document the
  pull-once-and-retag pattern (consumer's workaround: host pre-pulls
  each pushed ref and `docker tag`s the alias; tags are daemon-global
  so one retag serves every shard).

## Third finding (run 27445882960): published release carries STALE internal pins

The PUBLISHED `bonisoft3/sayt` repo's `v0.12.1` tag has `sayt/ci` calling

```
uses: bonisoft3/sayt/.github/actions/sayt/integrate@v0.11.0
```

— the copybara release rewrite turned the monorepo's relative
`./plugins/sayt/.github/actions/sayt/integrate` into a fully-qualified ref
pinned at the PREVIOUS release. integrate@v0.11.0 predates the
buildkit-syntax / SAYT_NO_CACHE_TO / BAYT_* threading, so the v0.12.1
release silently drops the frontend pin (inner bakes fail `--parents`
parse on depot) and the pull/image env. The composite's relative
`./.github/actions/sayt/ci` (consumer-workspace-resolved, needing the
consumer shim) plus this stale pin means the published action graph at
v0.12.1 never runs v0.12.1 integrate.

Fix: the release pipeline must rewrite internal refs to the release's
OWN tag (publish-then-retag, or template the version during sync).
Audit the v0.12.1 tag's other internal refs for the same staleness.

Also from the same run: the depot composite sets
`BAYT_IMAGE_TAG`/`BAYT_PULL_POLICY` as step env computed from
`push-images` — when `push-images=false`, they are EMPTY STRINGS that
mask any caller-provided env (step env beats job env). Thread them
non-clobbering (only set when push-images=true).
