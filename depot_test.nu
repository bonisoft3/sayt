#!/usr/bin/env nu
# Tests for sayt/depot's target resolution: the step that turns the `targets`
# input into the csv both baking phases consume.
# Run with: nu depot_test.nu (from plugins/sayt directory)

use std/assert

const ACTION = ".github/actions/sayt/depot/action.yml"
const STEP = "Resolve bake targets"

def main [] {
	print "Running sayt/depot tests...\n"

	if $nu.os-info.name == "windows" {
		print "    SKIP (composite-action steps are `shell: bash`)"
		return
	}

	test_empty_resolves_to_the_phase_default
	test_blank_input_is_empty_not_a_target
	test_every_line_of_a_block_scalar_survives
	test_commas_and_spaces_both_separate
	test_explicit_targets_keep_their_order
	test_bake_disables_attestations_by_flag
	test_rewrite_timestamp_keeps_its_epoch
	test_no_caller_value_reaches_the_exporter_list_unchecked
	test_no_cache_drops_the_import_and_leaves_the_export
	test_cache_tiers_stay_independently_gated
	test_no_cache_is_refused_where_it_would_be_inert
	test_every_cache_gate_is_a_bool
	test_an_unset_gate_lands_on_the_declared_default

	print "\nAll sayt/depot tests passed!"
}

# Runs the action's resolve step and returns its exit code plus the `targets`
# value it wrote to GITHUB_OUTPUT, which is what the phase steps read.
def resolve [phase: string, targets: string]: nothing -> record {
	let dir = (mktemp -d)
	let root = ($env.FILE_PWD? | default (pwd))

	let step = (open ($root | path join $ACTION) | get runs.steps | where name == $STEP | first)
	let script = ($dir | path join "step.sh")
	$step.run | save -f $script

	let out = ($dir | path join "github_output")
	touch $out
	let result = (do {
		with-env { PHASE: $phase, TARGETS: $targets, GITHUB_OUTPUT: $out } { ^/bin/bash $script }
	} | complete)

	let written = (open --raw $out | lines | where {|l| $l | str starts-with "targets=" } | first | default "")
	rm -rf $dir
	{ exit: $result.exit_code, targets: ($written | str replace "targets=" ""), stderr: $result.stderr }
}

def ok [r: record, ctx: string] {
	assert ($r.exit == 0) $"($ctx): expected exit 0, got ($r.exit): ($r.stderr)"
}

# Each phase substitutes its own default, which is why the input can default to
# empty. A shared default would make every build-phase caller that never sets
# `targets` ask for a target named `ci`.
def test_empty_resolves_to_the_phase_default [] {
	print "test empty resolves to the phase default..."
	let b = (resolve "build" "")
	ok $b "build"
	assert ($b.targets == "depot-build") $"build should default to the group, got: ($b.targets)"

	let f = (resolve "full" "")
	ok $f "full"
	assert ($f.targets == "ci") $"full should default to ci, got: ($f.targets)"
}

# Empty must never mean "build nothing": a caller with nothing to rebuild skips
# the action. Resolving blanks to a target named "" would bake nothing instead.
def test_blank_input_is_empty_not_a_target [] {
	print "test whitespace-only input falls back to the default..."
	let r = (resolve "build" "   \n \t ")
	ok $r "blank"
	assert ($r.targets == "depot-build") $"blank should be the default, got: ($r.targets)"
}

# `read` takes a single line, so a block scalar — the natural way to write a
# computed list — used to resolve to its first target and bake a silent subset.
def test_every_line_of_a_block_scalar_survives [] {
	print "test a multi-line targets input keeps every target..."
	let r = (resolve "build" "leaf-a\nleaf-b\nleaf-c\n")
	ok $r "block scalar"
	assert ($r.targets == "leaf-a,leaf-b,leaf-c") $"expected all three targets, got: ($r.targets)"
}

# The value crosses two callees that disagree on shape: `depot bake` takes argv
# words, `sayt integrate --target` one comma-separated value. Callers write
# either, so both must arrive as the same csv.
def test_commas_and_spaces_both_separate [] {
	print "test commas and spaces are interchangeable separators..."
	let spaced = (resolve "build" "leaf-a leaf-b")
	ok $spaced "spaced"
	let commas = (resolve "build" "leaf-a,leaf-b")
	ok $commas "comma"
	assert ($spaced.targets == $commas.targets) $"separators disagree: ($spaced.targets) vs ($commas.targets)"
	assert ($spaced.targets == "leaf-a,leaf-b") $"expected both targets, got: ($spaced.targets)"

	let mixed = (resolve "build" "a, b\nc")
	ok $mixed "mixed"
	assert ($mixed.targets == "a,b,c") $"expected all three targets, got: ($mixed.targets)"
}

def test_explicit_targets_keep_their_order [] {
	print "test explicit targets pass through unreordered..."
	let r = (resolve "full" "zeta alpha")
	ok $r "explicit"
	assert ($r.targets == "zeta,alpha") $"expected input order, got: ($r.targets)"
}

# BUILDX_NO_DEFAULT_ATTESTATIONS reads like it turns attestations off, but it
# never reaches a `depot bake` plan — `--print` resolves identically with and
# without it, while the flags resolve to `attest: [{disabled: true}]` per
# target. Relying on the env var costs an attestation manifest export per leaf
# and shows up nowhere: the bake still succeeds and sayt/summary, which counts
# RUN/ADD cache state, cannot see export work at all.
def test_bake_disables_attestations_by_flag [] {
	print "test the bake step turns attestations off in the plan, not by env..."
	let root = ($env.FILE_PWD? | default (pwd))
	let step = (open ($root | path join $ACTION) | get runs.steps
		| where name == "Bake + push runtime closure" | first)

	assert ($step.run =~ '--provenance=false') "bake step must pass --provenance=false"
	assert ($step.run =~ '--sbom=false') "bake step must pass --sbom=false"
	assert (not ($step.env | columns | any {|c| $c == "BUILDX_NO_DEFAULT_ATTESTATIONS" })) \
		"BUILDX_NO_DEFAULT_ATTESTATIONS is a no-op under depot bake; the flags carry this"
}

# rewrite-timestamp clamps layer mtimes to SOURCE_DATE_EPOCH and is inert
# without it — silently, not as an error: the bake succeeds and every layer
# keeps the mtimes the checkout gave it. An `env:` entry cannot express absent,
# only empty, so the step exports the epoch conditionally and refuses the pair.
def test_rewrite_timestamp_keeps_its_epoch [] {
	print "test the bake step pairs rewrite-timestamp with SOURCE_DATE_EPOCH..."
	let root = ($env.FILE_PWD? | default (pwd))
	let step = (open ($root | path join $ACTION) | get runs.steps
		| where name == "Bake + push runtime closure" | first)

	if ($step.run =~ 'rewrite-timestamp=') {
		assert ($step.run =~ '\$REWRITE_TIMESTAMP" = true \] && \[ -z "\$EPOCH"') \
			"an empty epoch must fail, not leave rewrite-timestamp inert and silently so"
	}
}

# BAYT_COMPOSE_OUTPUT is an exporter attribute list, so any caller value
# interpolated into it appends attributes rather than setting one: `name=` sends
# the push elsewhere, `force-compression=` (empty parses true) reinstates a full
# recompress. The bake would succeed either way. The codec is a constant and the
# one caller value left is a bool the step allowlists before composing.
def test_no_caller_value_reaches_the_exporter_list_unchecked [] {
	print "test the exporter list is a constant plus an allowlisted bool..."
	let root = ($env.FILE_PWD? | default (pwd))
	let step = (open ($root | path join $ACTION) | get runs.steps
		| where name == "Bake + push runtime closure" | first)

	assert (not ($step.env | columns | any {|c| $c == "BAYT_COMPOSE_OUTPUT" })) \
		"the exporter list must be composed after the allowlists, not interpolated in env:"
	assert ($step.run =~ 'compression=zstd,compression-level=3') \
		"the codec is a constant, pinned to a level so a buildkit default cannot move it"
	assert (not ($step.run =~ 'compression=\$')) \
		"no caller value may reach the compression attr"
	assert ($step.run =~ 'true\|false\) ;;') \
		"the step must allowlist the rewrite-timestamp bool"

	for bad in ["true,name=evil.example.com/x" "true,force-compression=" ""] {
		let r = (do { ^bash -c $"REWRITE_TIMESTAMP='($bad)'
			case \"$REWRITE_TIMESTAMP\" in
			  true|false) exit 0 ;;
			  *) exit 1 ;;
			esac" } | complete)
		assert equal $r.exit_code 1 $"($bad) must be rejected"
	}
}

# Runs the bake step against a `depot` shim on PATH and returns the argv it was
# invoked with, one element per line. Element-wise, not joined: a quoting
# regression that collapsed the four cache words into one unparseable argument
# satisfies any substring check.
#
# /bin/bash, not PATH bash: GitHub's `shell: bash` takes whatever PATH resolves
# to, which on the macOS runner is 3.2, where `"${a[@]}"` on an empty array is
# an unbound variable under `set -u`. Both cache gates on empties that array, so
# the step is only exercised honestly under the older shell — a homebrew bash on
# PATH would pass it.
def bake [--no-cache: string = "false", --cache-from: string = "false", --cache-to: string = "false"]: nothing -> list<string> {
	let dir = (mktemp -d)
	let root = ($env.FILE_PWD? | default (pwd))

	let step = (open ($root | path join $ACTION) | get runs.steps
		| where name == "Bake + push runtime closure" | first)
	let script = ($dir | path join "step.sh")
	$step.run | save -f $script

	let shim = ($dir | path join "depot")
	["#!/usr/bin/env bash" 'printf "%s\n" "$@"'] | str join "\n" | save -f $shim
	chmod +x $shim

	let result = (do {
		with-env {
			PATH: ([$dir] ++ $env.PATH)
			REWRITE_TIMESTAMP: "true"
			EPOCH: "0"
			CACHE_FROM: $cache_from
			CACHE_TO: $cache_to
			NO_CACHE: $no_cache
			TARGET_DIR: "guis/example"
			DEPOT_PROJECT_ID: "proj"
			BUILDKIT_SYNTAX: "docker/dockerfile:1.26"
			TARGETS: "depot-build"
			RUNNER_TEMP: $dir
		} { ^/bin/bash $script }
	} | complete)
	rm -rf $dir
	assert ($result.exit_code == 0) $"bake step exited ($result.exit_code): ($result.stderr)"
	$result.stdout | lines
}

# Runs the guard step and returns its exit code.
def guard [
	phase: string
	--no-cache: string = "false"
	--cache-from: string = "false"
	--cache-to: string = "false"
]: nothing -> int {
	let dir = (mktemp -d)
	let root = ($env.FILE_PWD? | default (pwd))
	let step = (open ($root | path join $ACTION) | get runs.steps
		| where name == "Validate cache inputs" | first)
	let script = ($dir | path join "step.sh")
	$step.run | save -f $script
	let result = (do {
		with-env {
			PHASE: $phase
			NO_CACHE: $no_cache
			CACHE_FROM: $cache_from
			CACHE_TO: $cache_to
		} { ^/bin/bash $script }
	} | complete)
	rm -rf $dir
	$result.exit_code
}

# A solve that reuses nothing has nothing to import. The export is the opposite:
# dropping it spends a full cold rebuild and leaves the next run to re-import
# the same pre-existing entries — and ci.yml sets `cache-to` on main, where that
# rebuild is most expensive.
def test_no_cache_drops_the_import_and_leaves_the_export [] {
	print "test no-cache drops the import and leaves the export to the caller..."
	let argv = (bake --no-cache "true" --cache-from "true" --cache-to "true")
	assert ("--no-cache" in $argv) $"expected --no-cache, got: ($argv)"
	assert ("*.cache-from=" in $argv) $"no-cache must strip cache-from, got: ($argv)"
	assert (not ("*.cache-to=" in $argv)) $"cache-to: true must survive no-cache, got: ($argv)"

	let no_export = (bake --no-cache "true" --cache-from "true")
	assert ("*.cache-to=" in $no_export) $"cache-to: false must still be stripped, got: ($no_export)"
}

# The two tiers are gated apart so trunk can export while branches import for
# free. Every bake in a run shares one depot cache namespace, so a default bake
# that picked up --no-cache would cold-start the lot.
def test_cache_tiers_stay_independently_gated [] {
	print "test the registry tiers stay independently gated without no-cache..."
	let both = (bake --cache-from "true" --cache-to "true")
	assert (not ("--no-cache" in $both)) $"an unset no-cache must not reach the bake: ($both)"
	assert (not ("*.cache-from=" in $both)) $"cache-from: true must survive: ($both)"
	assert (not ("*.cache-to=" in $both)) $"cache-to: true must survive: ($both)"

	let read_only = (bake --cache-from "true")
	assert (not ("*.cache-from=" in $read_only)) $"cache-from: true must survive: ($read_only)"
	assert ("*.cache-to=" in $read_only) $"cache-to: false must be stripped: ($read_only)"
}

# The other phases bake through sayt/ci, which has no such input, so a `true`
# there would do nothing at all.
def test_no_cache_is_refused_where_it_would_be_inert [] {
	print "test no-cache is refused on the phases that would ignore it..."
	assert equal (guard "build" --no-cache "true") 0 "build honours no-cache"
	assert equal (guard "full" --no-cache "false") 0 "an explicit no is fine on any phase"
	assert equal (guard "full" --no-cache "true") 1 "phase full cannot honour no-cache"
	assert equal (guard "run" --no-cache "true") 1 "phase run bakes nothing"
}

# All three gates are read with `= "true"` downstream, so a non-bool strips a
# tier and says nothing.
def test_every_cache_gate_is_a_bool [] {
	print "test every cache gate is refused a non-bool..."
	for bad in ["yes" "1" "True" "on"] {
		assert equal (guard "build" --no-cache $bad) 1 $"no-cache=($bad) must be refused"
		assert equal (guard "build" --cache-from $bad) 1 $"cache-from=($bad) must be refused"
		assert equal (guard "full" --cache-to $bad) 1 $"cache-to=($bad) must be refused"
	}
	for phase in ["build" "full" "run"] {
		assert equal (guard $phase --no-cache "" --cache-from "" --cache-to "") 0 \
			$"unset gates must pass on ($phase)"
	}
}

# Empty is an unset input threaded in, so the guard lets it through and the bake
# step reads it with the same `= "true"` as everything else. That is only safe
# while each gate defaults to the value that comparison gives it, which is what
# this pins: flip a `default:` to "true" and the two stop agreeing.
def test_an_unset_gate_lands_on_the_declared_default [] {
	print "test an unset gate lands on the declared default..."
	let inputs = (open (($env.FILE_PWD? | default (pwd)) | path join $ACTION) | get inputs)
	let declared = {|name| $inputs | get $name | get default }

	assert equal (bake --no-cache "") (bake --no-cache (do $declared "no-cache")) "no-cache"
	assert equal (bake --cache-from "") (bake --cache-from (do $declared "cache-from")) "cache-from"
	assert equal (bake --cache-to "") (bake --cache-to (do $declared "cache-to")) "cache-to"
}
