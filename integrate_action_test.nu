#!/usr/bin/env nu
# Tests for sayt/integrate under an act replay, which has none of CI's
# accounts: a gha cache export 404s, failing the bake after the test passed.
# Run with: nu integrate_action_test.nu (from plugins/sayt directory)

use std/assert

const ACTION = ".github/actions/sayt/integrate/action.yml"

def main [] {
	print "Running sayt/integrate action tests...\n"

	if $nu.os-info.name == "windows" {
		print "    SKIP (composite-action steps are `shell: bash`)"
		return
	}

	test_act_turns_the_cache_gate_off
	test_github_keeps_the_cache_gate
	test_act_runs_without_remote_caches
	test_github_passes_flags_through

	print "\nAll sayt/integrate action tests passed!"
}

def step-script [name: string, dir: string]: nothing -> string {
	let root = ($env.FILE_PWD? | default (pwd))
	let step = (open ($root | path join $ACTION) | get runs.steps | where name == $name | first)
	let script = ($dir | path join "step.sh")
	$step.run | save -f $script
	$script
}

# Runs `body` under exactly the case's environment as far as act goes: an ACT
# the runner itself carries would answer every "GitHub" case as act.
def as-case [vars: record, body: closure]: nothing -> any {
	hide-env -i ACT
	with-env $vars $body
}

def gate [extra: record]: nothing -> string {
	let dir = (mktemp -d)
	let script = (step-script "Resolve cache gate" $dir)
	let out = ($dir | path join "github_output")
	touch $out
	as-case ({ ACTION_CACHE: "true", MODE: "compose", GITHUB_OUTPUT: $out } | merge $extra) { ^/bin/bash $script }
	let active = (open --raw $out | lines | where {|l| $l | str starts-with "active=" } | first)
	rm -rf $dir
	$active | str replace "active=" ""
}

# Runs the `sayt integrate` step against a stub `sayt` that prints its argv.
# `mode: local` keeps the step's `${{ inputs.target }}` line, which only the
# runner expands, out of the bash that runs here.
def invoke [extra: record]: nothing -> list<string> {
	let dir = (mktemp -d)
	let script = (step-script "sayt integrate" $dir)
	let bin = ($dir | path join "bin")
	mkdir $bin
	"#!/bin/sh\nfor a in \"$@\"; do echo \"$a\"; done\n" | save -f ($bin | path join "sayt")
	^chmod +x ($bin | path join "sayt")
	let result = (as-case ({ MODE: "local", FLAGS: "--with-host-env", PATH: ($env.PATH | prepend $bin) } | merge $extra) {
		^/bin/bash $script | complete
	})
	rm -rf $dir
	assert equal $result.exit_code 0 $result.stderr
	$result.stdout | lines
}

def test_act_turns_the_cache_gate_off [] {
	print "  act turns the cache gate off"
	assert equal (gate { ACT: "true" }) "false"
	print "    PASS"
}

def test_github_keeps_the_cache_gate [] {
	print "  GitHub keeps the cache gate"
	assert equal (gate {}) "true"
	print "    PASS"
}

def test_act_runs_without_remote_caches [] {
	print "  act runs without remote caches"
	let args = (invoke { ACT: "true" })
	assert ("--no-cache-from" in $args) $"argv: ($args)"
	assert ("--no-cache-to" in $args) $"argv: ($args)"
	assert ("--with-host-env" in $args) $"argv: ($args)"
	print "    PASS"
}

def test_github_passes_flags_through [] {
	print "  GitHub passes flags through"
	assert equal (invoke {}) ["integrate" "--with-host-env"]
	print "    PASS"
}
