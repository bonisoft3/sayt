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
		with-env { PHASE: $phase, TARGETS: $targets, GITHUB_OUTPUT: $out } { ^bash $script }
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
