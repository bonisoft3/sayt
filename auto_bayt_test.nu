#!/usr/bin/env nu
# Tests for auto-bayt.nu layout detection.
# Run with: nu auto_bayt_test.nu (from plugins/sayt directory)

use std/assert

def main [] {
	print "Running auto-bayt tests...\n"

	test_external_layout_uses_path_bayt
	test_nop_without_bayt_cue

	print "\nAll auto-bayt tests passed!"
}

# Without a sibling bayt checkout (mise http-tarball layout), auto-bayt
# runs `bayt generate` from PATH.
def test_external_layout_uses_path_bayt [] {
	print "test external layout runs bayt from PATH..."
	let tmpdir = (mktemp -d)
	let distro = $tmpdir | path join "sayt"
	mkdir $distro
	cp auto-bayt.nu $distro
	cp tools.nu $distro
	glob *.toml | each { |f| cp $f $distro }
	let bin = $tmpdir | path join "bin"
	mkdir $bin
	$"#!/bin/sh\necho \"FAKE_BAYT $@\" > ($tmpdir)/called\n" | save ($bin | path join "bayt")
	chmod +x ($bin | path join "bayt")
	let proj = $tmpdir | path join "proj"
	mkdir $proj
	"project: {}" | save ($proj | path join "bayt.cue")

	let result = (do {
		cd $proj
		with-env { PATH: ([$bin] ++ $env.PATH) } {
			nu -c $"use ($distro)/auto-bayt.nu; auto-bayt"
		}
	} | complete)
	assert ($result.exit_code == 0) $"expected 0, got ($result.exit_code): ($result.stderr)"
	let called = (open ($tmpdir | path join "called") | str trim)
	assert ($called == "FAKE_BAYT generate") $"expected 'FAKE_BAYT generate', got: ($called)"
	rm -rf $tmpdir
}

# Projects without bayt.cue skip the rule entirely.
def test_nop_without_bayt_cue [] {
	print "test nop without bayt.cue..."
	let tmpdir = (mktemp -d)
	let distro = $tmpdir | path join "sayt"
	mkdir $distro
	cp auto-bayt.nu $distro
	cp tools.nu $distro
	glob *.toml | each { |f| cp $f $distro }
	let proj = $tmpdir | path join "proj"
	mkdir $proj

	let result = (do {
		cd $proj
		nu -c $"use ($distro)/auto-bayt.nu; auto-bayt"
	} | complete)
	assert ($result.exit_code == 0) $"expected nop exit 0, got ($result.exit_code): ($result.stderr)"
	rm -rf $tmpdir
}
