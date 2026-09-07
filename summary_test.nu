#!/usr/bin/env nu
# Tests for sayt/summary's artifact naming: the step that turns the `name`
# input into the artifact names and the record's path.
# Run with: nu summary_test.nu (from plugins/sayt directory)

use std/assert

const ACTION = ".github/actions/sayt/summary/action.yml"
const STEP = "Resolve artifact path"

def main [] {
	print "Running sayt/summary tests...\n"

	if $nu.os-info.name == "windows" {
		print "    SKIP (composite-action steps are `shell: bash`)"
		return
	}

	test_a_plain_name_is_left_alone
	test_a_target_with_a_slash_is_a_legal_artifact_name
	test_the_record_path_holds_no_directory_the_step_never_made
	test_an_explicit_prefix_is_kept

	print "\nAll sayt/summary tests passed."
}

# Runs the step and hands back everything it wrote to GITHUB_OUTPUT, which is
# what the upload steps read.
def names [name: string, --prefix: string = ""]: nothing -> record {
	let dir = (mktemp -d)
	let root = ($env.FILE_PWD? | default (pwd))

	let step = (open ($root | path join $ACTION) | get runs.steps | where name == $STEP | first)
	let script = ($dir | path join "step.sh")
	$step.run | save -f $script

	let out = ($dir | path join "github_output")
	touch $out
	let result = (do {
		with-env {
			SAYT_SUMMARY_NAME: $name, ARTIFACT_PREFIX: $prefix,
			GITHUB_REPOSITORY: "worldsense/trash", RUNNER_TEMP: $dir, GITHUB_OUTPUT: $out,
		} { ^/bin/bash $script }
	} | complete)

	let wrote = (open --raw $out | lines | reduce --fold {} {|l, acc|
		$acc | insert ($l | split row "=" | first) ($l | split row "=" | skip 1 | str join "=")
	})
	rm -rf $dir
	assert ($result.exit_code == 0) $"expected exit 0, got ($result.exit_code): ($result.stderr)"
	$wrote
}

# GitHub refuses a forward slash in an artifact name, and a target names a
# directory — so every target under guis/ or apps/ carries one.
const ILLEGAL = ["/", "\\", ":", "<", ">", "|", "*", "?", "\""]

def legal [n: string, ctx: string] {
	for c in $ILLEGAL {
		assert (not ($n | str contains $c)) $"($ctx): artifact name ($n) carries ($c)"
	}
}

def test_a_plain_name_is_left_alone [] {
	let r = (names "boxer")
	assert equal $r.name "worldsense~trash~boxer.dockerbuild"
	assert equal $r."log-name" "worldsense~trash~boxer.bake-log"
	print "  ok: a plain name is left alone"
}

def test_a_target_with_a_slash_is_a_legal_artifact_name [] {
	let r = (names "guis/iris")
	legal $r.name "dockerbuild"
	legal $r."log-name" "bake-log"
	assert equal $r.name "worldsense~trash~guis-iris.dockerbuild"
	assert equal $r."log-name" "worldsense~trash~guis-iris.bake-log"
	print "  ok: a target with a slash is a legal artifact name"
}

# The path is where the build record is written and then read from. A slash in
# it names a directory the step never created, so the record went nowhere and
# the upload skipped without saying why.
def test_the_record_path_holds_no_directory_the_step_never_made [] {
	let r = (names "apps/thenote")
	let tail = ($r.path | path basename)
	assert equal $tail "sayt-summary-apps-thenote.dockerbuild"
	assert (not (($r.path | path dirname | path basename) == "apps")) "the record still lands in a directory nothing made"
	print "  ok: the record path holds no directory the step never made"
}

def test_an_explicit_prefix_is_kept [] {
	let r = (names "guis/iris" --prefix "mine~")
	assert equal $r.name "mine~guis-iris.dockerbuild"
	print "  ok: an explicit prefix is kept"
}

main
