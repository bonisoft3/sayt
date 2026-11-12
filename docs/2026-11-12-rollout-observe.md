---
type: decision
title: rollout / observe
description: Names the verb pair above release / verify — rollout puts a released artifact in front of the people who use it, observe checks it is working for them — and argues why it is not called deploy.
status: unbuilt
---

# rollout / observe

The ladder gains a sixth pair. Nothing of it is built: `config.cue` knows ten
verbs, and `rollout` and `observe` are only reserved names.

| Do | Check | Default platform | The pair answers |
| --- | --- | --- | --- |
| `setup` | `doctor` | `bare` | are the tools here |
| `generate` | `lint` | `repo` | is the source consistent |
| `build` | `test` | `host` | does the unit work |
| `launch` | `integrate` | `compose` | does it work with its neighbours |
| `release` | `verify` | `preview` | is it available for adoption |
| `rollout` | `observe` | `production` | are people using it, and is it working for them |

## The line against release

`release` makes a thing available for adoption: it pushes to a staging
environment or publishes assets that can be downloaded. It creates the
adoptable artifact and stops there; nobody has to be using it.

`rollout` creates nothing. It takes what `release` produced and changes who
gets it: shifts traffic, moves the stable tag, marks a download as current.
A rollout that has to build is a release that was skipped.

`verify` probes the released thing: synthetic checks against the artifact or
the staging environment. `observe` reads what real use reports — error rates,
objectives, a canary against its baseline. `verify` can pass with no users;
`observe` has nothing to read without them.

## Why not deploy

`deploy` names a mechanism, putting bits on machines, and that mechanism
already runs inside `launch` (a compose stack), `release` (a preview
environment) and `rollout`. A verb named for it would overlap all three, which
is why deploy and release read as the same step. The ladder names what each
step establishes, not how.

## Alternatives

- **`promote` / `observe`** says most plainly that nothing new is built, but
  it describes the artifact's move between stages, not people coming to use
  it, and gradual exposure is not in the word.
- **`publish` / `observe`** is what `release` already means for downloadable
  assets.
- **`serve` or `operate` / `monitor`** name a state that never finishes; every
  other verb is an action that ends with an exit code.

## Undefined for now

The names and the default platform are the whole decision. What the built-in
`rollout` and `observe` run, what `production` means beyond a rule filter, and
whether `observe` exits and on what evidence are left to whoever builds them.
