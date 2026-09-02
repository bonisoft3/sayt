#!/usr/bin/env nu
# Tests for sayt/ci's capability-flag step: the bash that turns the action's
# cache gates into `sayt integrate` flags.
# Run with: nu ci_test.nu (from plugins/sayt directory)

use std/assert

const ACTION = ".github/actions/sayt/ci/action.yml"
const STEP = "Compute capability flags"

def main [] {
	print "Running sayt/ci tests...\n"

	if $nu.os-info.name == "windows" {
		print "    SKIP (composite-action steps are `shell: bash`)"
		return
	}

	test_a_non_bool_cache_gate_is_refused
	test_an_unset_gate_lands_on_the_declared_default

	print "\nAll sayt/ci tests passed!"
}

def action []: nothing -> record {
	open (($env.FILE_PWD? | default (pwd)) | path join $ACTION)
}

# Runs the flag step and returns its exit code plus the flags it wrote.
# /bin/bash rather than PATH bash — see depot_test.nu's `bake`.
def compute [cache_from: string, cache_to: string]: nothing -> record {
	let dir = (mktemp -d)
	let step = (action | get runs.steps | where name == $STEP | first)
	let script = ($dir | path join "step.sh")
	$step.run | save -f $script

	let out = ($dir | path join "github_output")
	touch $out
	let result = (do {
		with-env {
			WITH_BUILDX: "true"
			CACHE_FROM: $cache_from
			CACHE_TO: $cache_to
			GITHUB_OUTPUT: $out
		} { ^/bin/bash $script }
	} | complete)
	let written = (open --raw $out | lines | where {|l| $l | str starts-with "flags=" } | append "" | first)
	rm -rf $dir
	{ exit: $result.exit_code, flags: ($written | str replace "flags=" "") }
}

# The gates are read with `= "true"`, which turns `yes`, `1` or a generated
# `True` into `false`: a caller who meant "cache on" gets a cold build and no
# diagnostic.
def test_a_non_bool_cache_gate_is_refused [] {
	print "test a non-bool cache gate fails instead of reading as false..."
	for bad in ["yes" "1" "True" "TRUE" "on"] {
		assert equal (compute $bad "true").exit 1 $"cache-from=($bad) must be refused"
		assert equal (compute "true" $bad).exit 1 $"cache-to=($bad) must be refused"
	}
	assert equal (compute "false" "false").flags "--dind-bridge --with-buildx --no-cache-from --no-cache-to" \
		"an explicit false must still strip its tier"
}

# Empty is a caller threading an unset input. Both gates default to on, so the
# bare comparison would read it as off; the step normalises to a literal, which
# is what drifts if a default moves.
def test_an_unset_gate_lands_on_the_declared_default [] {
	print "test an unset gate lands on the declared default..."
	let inputs = (action | get inputs)
	for name in ["cache-from" "cache-to"] {
		let declared = ($inputs | get $name | get default)
		let as_declared = (if $name == "cache-from" { compute $declared "true" } else { compute "true" $declared })
		let as_empty = (if $name == "cache-from" { compute "" "true" } else { compute "true" "" })
		assert equal $as_empty.exit 0 $"($name) empty must be accepted"
		assert equal $as_empty.flags $as_declared.flags $"($name) empty must match its declared default ($declared)"
	}
}
