#!/usr/bin/env nu
# Tests for sayt/plan's retag step: the step that turns a leaf set into the
# build plan, by attempting the retag each hit needs.
#
# `docker` is stubbed on PATH. The stub records every invocation, which is how
# the empty-input case is asserted: the bug it guards is the registry being
# called at all, not a wrong answer.
#
# Run with: nu plan_test.nu (from plugins/sayt directory)

use std/assert

const ACTION = ".github/actions/sayt/plan/action.yml"
const STEP = "Retag published leaves"

def main [] {
	print "Running sayt/plan tests...\n"

	if $nu.os-info.name == "windows" {
		print "    SKIP (composite-action steps are `shell: bash`)"
		return
	}

	test_empty_input_never_calls_the_registry
	test_malformed_input_plans_nothing
	test_all_published_reports_all_hit
	test_none_published_names_every_target
	test_partial_names_only_the_misses
	test_a_dead_worker_counts_as_a_miss
	test_auth_failure_is_called_out_as_auth
	test_seed_tags_the_fingerprint_from_the_build_tag
	test_seed_on_empty_input_never_calls_the_registry
	test_a_templated_repo_is_expanded_against_the_env
	test_an_unhashable_leaf_is_a_miss_and_is_never_probed
	test_a_repo_expanding_to_nothing_is_a_miss
	test_seed_refuses_a_ref_outside_seed_from
	test_seed_accepts_any_branch_with_a_star
	test_plan_ignores_seed_from

	print "\nAll sayt/plan tests passed!"
}

# Runs the action's plan step against a stubbed docker and returns its outputs
# plus the calls the stub saw.
def plan [leaves: string, published: list<string>, --fail-mode: string = "notfound", --mode: string = "plan", --branch: string = "main", --seed-from: string = "main"]: nothing -> record {
	let dir = (mktemp -d)
	let root = ($env.FILE_PWD? | default (pwd))

	let step = (open ($root | path join $ACTION) | get runs.steps | where name == $STEP | first)
	let script = ($dir | path join "step.sh")
	$step.run | save -f $script

	# The stub answers from a published-refs file: a `create` whose SOURCE ref
	# is listed succeeds, anything else fails the way the registry would.
	let bin = ($dir | path join "bin")
	mkdir $bin
	($published | str join "\n") | save -f ($dir | path join "published")
	# Single-quoted so nothing here is nu interpolation: the `$6`/`$src` are the
	# stub's own shell variables.
	let stub = ('#!/bin/sh
echo "$@" >> "__DIR__/calls"
src=$6
if grep -qxF "$src" "__DIR__/published"; then exit 0; fi
if [ "__FAILMODE__" = "auth" ]; then
  echo "unauthorized: authentication required" >&2
else
  echo "$src: not found: manifest unknown" >&2
fi
exit 1
' | str replace --all "__DIR__" $dir | str replace --all "__FAILMODE__" $fail_mode)
	$stub | save -f ($bin | path join "docker")
	^chmod +x ($bin | path join "docker")

	let out = ($dir | path join "github_output")
	touch $out
	touch ($dir | path join "calls")

	let result = (do {
		with-env {
			LEAVES: $leaves
			TAG: "abc123"
			MODE: $mode
			GITHUB_HEAD_REF: ""
			GITHUB_REF_NAME: $branch
			SEED_FROM: $seed_from
			CONCURRENCY: "4"
			DEPOT_ORG_ID: "orgid"
			GITHUB_OUTPUT: $out
			GITHUB_STEP_SUMMARY: ""
			PATH: $"($bin):($env.PATH | split row (char esep) | str join (char esep))"
		} { ^bash $script }
	} | complete)

	let written = (open --raw $out | lines)
	let calls = (open --raw ($dir | path join "calls") | lines | where { |l| ($l | str trim) != "" })
	rm -rf $dir
	{
		exit:    $result.exit_code
		targets: ($written | where { |l| $l | str starts-with "build-targets=" } | first | default "build-targets=" | str replace "build-targets=" "")
		all_hit: ($written | where { |l| $l | str starts-with "all-hit=" } | first | default "all-hit=" | str replace "all-hit=" "")
		calls:   $calls
		stderr:  $result.stderr
	}
}

def leaf [target: string, fp: string]: nothing -> record {
	{target: $target, repo: $"registry.example/bayt-($target)", fingerprint: $fp}
}

# GNU xargs runs its command once on empty input; with no arguments `$0` falls
# back to `sh`, so the registry is asked for a repository named `sh` and the
# step dies with an authorization error that is not one. The assertion is on
# the call count, because a wrong answer is not the failure mode — any call at
# all is.
def test_empty_input_never_calls_the_registry [] {
	let r = (plan "[]" [])
	assert equal $r.exit 0
	assert equal $r.calls []
	assert equal $r.targets ""
	assert equal $r.all_hit "false"
	print "  PASS  empty input never calls the registry"
}

# Fail open: only a positive registry result licenses a skip.
def test_malformed_input_plans_nothing [] {
	let r = (plan "not json at all" [])
	assert equal $r.exit 0
	assert equal $r.calls []
	assert equal $r.targets ""
	assert equal $r.all_hit "false"
	print "  PASS  malformed input plans nothing"
}

# all-hit is what lets the caller skip the build step. An empty build-targets
# cannot carry it: `sayt/depot` reads empty as the whole group.
def test_all_published_reports_all_hit [] {
	let ls = ([(leaf "a" "h1") (leaf "b" "h2")] | to json)
	let r = (plan $ls ["registry.example/bayt-a:fp-h1" "registry.example/bayt-b:fp-h2"])
	assert equal $r.exit 0
	assert equal $r.all_hit "true"
	assert equal $r.targets ""
	assert equal ($r.calls | length) 2
	print "  PASS  every leaf published reports all-hit"
}

def test_none_published_names_every_target [] {
	let ls = ([(leaf "a" "h1") (leaf "b" "h2")] | to json)
	let r = (plan $ls [])
	assert equal $r.exit 0
	assert equal $r.all_hit "false"
	assert equal $r.targets "a,b"
	print "  PASS  nothing published names every target"
}

def test_partial_names_only_the_misses [] {
	let ls = ([(leaf "a" "h1") (leaf "b" "h2") (leaf "c" "h3")] | to json)
	let r = (plan $ls ["registry.example/bayt-a:fp-h1" "registry.example/bayt-c:fp-h3"])
	assert equal $r.exit 0
	assert equal $r.all_hit "false"
	assert equal $r.targets "b"
	print "  PASS  a partial plan names only the misses"
}

# A hit is a positive result, so anything short of one must build. A worker
# that dies leaves no result file at all.
def test_a_dead_worker_counts_as_a_miss [] {
	let ls = ([(leaf "a" "h1")] | to json)
	# An empty fingerprint still forms a ref, so the stub answers it normally;
	# the point is that a ref the stub never publishes is never a hit.
	let r = (plan $ls ["registry.example/bayt-a:fp-somethingelse"])
	assert equal $r.all_hit "false"
	assert equal $r.targets "a"
	print "  PASS  anything short of a hit builds"
}

# A 401 read as "not published" rebuilds forever while looking like a cache
# regression, so the miss path has to name it.
def test_auth_failure_is_called_out_as_auth [] {
	let ls = ([(leaf "a" "h1") (leaf "b" "h2")] | to json)
	let r = (plan $ls [] --fail-mode "auth")
	assert equal $r.exit 0
	assert equal $r.targets "a,b"
	assert ($r.stderr | str contains "credentials, not cache") $"expected an auth diagnosis, got: ($r.stderr)"
	print "  PASS  an auth failure is reported as auth, not as a cache miss"
}

# seed runs the same copy in the other direction: what the bake just pushed as
# `<repo>:<tag>` becomes `<repo>:fp-<hash>`, which is what a later plan hits.
def test_seed_tags_the_fingerprint_from_the_build_tag [] {
	let ls = ([(leaf "a" "h1")] | to json)
	# In seed mode the SOURCE is the build tag, so that is what the stub must
	# hold for the copy to succeed.
	let r = (plan $ls ["registry.example/bayt-a:abc123"] --mode "seed")
	assert equal $r.exit 0
	assert equal ($r.calls | length) 1
	assert ($r.calls | first | str contains "-t registry.example/bayt-a:fp-h1 registry.example/bayt-a:abc123") $"seed copied the wrong direction: ($r.calls | first)"
	print "  PASS  seed tags the fingerprint from the build tag"
}

# The xargs trap is direction-independent, so the guard has to hold for seed
# too — an all-hit plan seeds nothing, which is exactly when it would fire.
def test_seed_on_empty_input_never_calls_the_registry [] {
	let r = (plan "[]" [] --mode "seed")
	assert equal $r.exit 0
	assert equal $r.calls []
	print "  PASS  seed on empty input never calls the registry"
}

# depot.json keeps ${VAR:-default} literal so the file is environment-
# independent. Expanding is the action's job: a caller that did it would be
# reimplementing this per workflow, and the default arm is easy to drop.
def test_a_templated_repo_is_expanded_against_the_env [] {
	# DEPOT_ORG_ID is set in the harness; DEPOT_PROJECT_ID is not, so its
	# default has to carry.
	let ls = ([{
		target: "a"
		repo: "${DEPOT_ORG_ID:-fallback}.reg.example/${DEPOT_PROJECT_ID:-proj}/bayt-a"
		fingerprint: "h1"
	}] | to json)
	let r = (plan $ls ["orgid.reg.example/proj/bayt-a:fp-h1"])
	assert equal $r.all_hit "true" $"expansion did not resolve: ($r.calls)"
	print "  PASS  a templated repo is expanded against the env"
}

# A leaf the caller could not hash arrives with an empty fingerprint. It must
# build, and it must never be probed: `fp-` is a tag every unhashable leaf in
# a repo would answer to, so a stale one would read as a hit.
def test_an_unhashable_leaf_is_a_miss_and_is_never_probed [] {
	let ls = ([{target: "a", repo: "registry.example/bayt-a", fingerprint: ""}
	           (leaf "b" "h2")] | to json)
	let r = (plan $ls ["registry.example/bayt-b:fp-h2"])
	assert equal $r.exit 0
	assert equal $r.targets "a"
	assert equal $r.all_hit "false"
	# One call, for b. Nothing was asked about a.
	assert equal ($r.calls | length) 1
	print "  PASS  an unhashable leaf is a miss and is never probed"
}

# A `${VAR}` with no default and no value expands to nothing. The row must not
# reach xargs: it collapses whitespace, so a short row takes its third field
# from the NEXT leaf's row and every later result lands against the wrong
# index — in seed mode that writes a fingerprint tag onto another repository.
def test_a_repo_expanding_to_nothing_is_a_miss [] {
	let ls = ([{target: "a", repo: "${NOT_SET_ANYWHERE}", fingerprint: "h1"}
	           (leaf "b" "h2")] | to json)
	let r = (plan $ls ["registry.example/bayt-b:fp-h2"])
	assert equal $r.exit 0
	assert equal $r.targets "a"
	# b still resolved against its own fingerprint, not a's stolen field.
	assert equal ($r.calls | length) 1
	assert ($r.calls | first | str contains "registry.example/bayt-b:fp-h2") $"b was probed with the wrong ref: ($r.calls | first)"
	print "  PASS  a repo expanding to nothing is a miss"
}

# A seed is what a later run ships instead of building, so this path fails
# CLOSED where every other one fails open.
def test_seed_refuses_a_ref_outside_seed_from [] {
	let ls = ([(leaf "a" "h1")] | to json)
	let r = (plan $ls ["registry.example/bayt-a:abc123"] --mode "seed" --branch "feature/x")
	assert equal $r.exit 0
	assert equal $r.calls []
	assert ($r.stderr | str contains "not seeding") $"expected a refusal, got: ($r.stderr)"
	print "  PASS  seed refuses a branch that is not seed-from"
}

# `*` is the documented opt-out, and it must actually seed.
def test_seed_accepts_any_branch_with_a_star [] {
	let ls = ([(leaf "a" "h1")] | to json)
	let r = (plan $ls ["registry.example/bayt-a:abc123"] --mode "seed" --branch "feature/x" --seed-from "*")
	assert equal $r.exit 0
	assert equal ($r.calls | length) 1
	print "  PASS  seed-from `*` seeds from any branch"
}

# Reading a fingerprint tag is always allowed: a missed read costs a rebuild.
def test_plan_ignores_seed_from [] {
	let ls = ([(leaf "a" "h1")] | to json)
	let r = (plan $ls ["registry.example/bayt-a:fp-h1"] --branch "feature/x")
	assert equal $r.all_hit "true" $"plan must not be gated by seed-from: ($r.stderr)"
	print "  PASS  plan is not gated by seed-from"
}
