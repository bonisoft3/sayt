#!/usr/bin/env nu
# Tests for auto-bayt.nu layout detection and generator environment.
# Run with: nu auto_bayt_test.nu (from plugins/sayt directory)

use std/assert

def main [] {
	print "Running auto-bayt tests...\n"

	test_external_layout_uses_path_bayt
	test_nop_without_bayt_cue
	# The shim auto-bayt writes is a shell script, which Windows cannot load as
	# a cli-plugin, so there is no DOCKER_CONFIG to assert there.
	if $nu.os-info.name == "windows" {
		test_docker_env_empty_on_windows
	} else {
		test_pinned_compose_docker_config
		test_sibling_layout_gets_docker_config
		test_docker_env_export
	}

	print "\nAll auto-bayt tests passed!"
}

# PATH lookup on Windows executes only known extensions, so a fake named
# `bayt` with a shebang is invisible there.
def install-fake-bayt [bin: path, sink: path] {
	if $nu.os-info.name == "windows" {
		$"@echo off\r\necho FAKE_BAYT %* > \"($sink)\"\r\n" | save -f ($bin | path join "bayt.cmd")
	} else {
		$"#!/bin/sh\necho \"FAKE_BAYT $@\" > ($sink)\n" | save -f ($bin | path join "bayt")
		^chmod +x ($bin | path join "bayt")
	}
}

# Shared fixture: copied sayt distro, a bin dir for fakes, and a project
# dir (with bayt.cue unless --no-bayt-cue).
def setup-fixture [--no-bayt-cue]: nothing -> record {
	let tmpdir = (mktemp -d)
	let distro = ($tmpdir | path join "sayt")
	mkdir $distro
	cp auto-bayt.nu $distro
	cp tools.nu $distro
	glob *.toml | each { |f| cp $f $distro }
	let bin = ($tmpdir | path join "bin")
	mkdir $bin
	let proj = ($tmpdir | path join "proj")
	mkdir $proj
	if not $no_bayt_cue {
		"project: {}" | save ($proj | path join "bayt.cue")
	}
	{tmpdir: $tmpdir, distro: $distro, bin: $bin, proj: $proj}
}

def run-auto-bayt [fx: record]: nothing -> record {
	let searched = ([$fx.bin] ++ $env.PATH)
	# Windows spawns children from `Path`; nu surfaces that same variable as
	# `PATH`, so setting only one leaves the child searching the original.
	let injected = if $nu.os-info.name == "windows" {
		{PATH: $searched, Path: $searched}
	} else {
		{PATH: $searched}
	}
	do {
		cd $fx.proj
		with-env $injected {
			nu -c $"use ($fx.distro)/auto-bayt.nu; auto-bayt"
		}
	} | complete
}

# Without a sibling bayt checkout (mise http-tarball layout), auto-bayt
# runs `bayt generate` from PATH.
def test_external_layout_uses_path_bayt [] {
	print "test external layout runs bayt from PATH..."
	let fx = (setup-fixture)
	install-fake-bayt $fx.bin ($fx.tmpdir | path join "called")

	let result = (run-auto-bayt $fx)
	assert ($result.exit_code == 0) $"expected 0, got ($result.exit_code): ($result.stderr)"
	let called = (open ($fx.tmpdir | path join "called") | str trim)
	assert ($called == "FAKE_BAYT generate") $"expected 'FAKE_BAYT generate', got: ($called)"
	rm -rf $fx.tmpdir
}

# Projects without bayt.cue skip the rule entirely.
def test_nop_without_bayt_cue [] {
	print "test nop without bayt.cue..."
	let fx = (setup-fixture --no-bayt-cue)

	let result = (run-auto-bayt $fx)
	assert ($result.exit_code == 0) $"expected nop exit 0, got ($result.exit_code): ($result.stderr)"
	rm -rf $fx.tmpdir
}

# The generator's `docker compose` resolves via plugin search, so auto-bayt
# must hand it a DOCKER_CONFIG whose cli-plugins holds a shim routing to
# sayt's pinned compose — otherwise generate output varies with the host's
# installed compose (e.g. Docker Desktop's).
def test_pinned_compose_docker_config [] {
	print "test generator runs under a DOCKER_CONFIG with a compose shim..."
	let fx = (setup-fixture)
	$"#!/bin/sh\necho \"$DOCKER_CONFIG\" > ($fx.tmpdir)/dockercfg\n" | save ($fx.bin | path join "bayt")
	^chmod +x ($fx.bin | path join "bayt")

	let result = (run-auto-bayt $fx)
	assert ($result.exit_code == 0) $"expected 0, got ($result.exit_code): ($result.stderr)"
	assert-pinned-shim $fx
	rm -rf $fx.tmpdir
}

# The sibling-checkout (monorepo) layout must get the same DOCKER_CONFIG;
# narrowing the with-env to the PATH branch would silently unpin the
# layout this repo itself uses.
def test_sibling_layout_gets_docker_config [] {
	print "test sibling layout gets DOCKER_CONFIG..."
	let fx = (setup-fixture)
	let core = ($fx.tmpdir | path join "bayt" "core")
	mkdir $core
	let sink = ($fx.tmpdir | path join "dockercfg")
	("export def main [--runtime: string = \"\"] { ($env.DOCKER_CONFIG? | default \"\") | save -f " + $sink + " }")
		| save ($core | path join "generate.nu")

	let result = (run-auto-bayt $fx)
	assert ($result.exit_code == 0) $"expected 0, got ($result.exit_code): ($result.stderr)"
	assert-pinned-shim $fx
	rm -rf $fx.tmpdir
}

# The Windows half of the contract the three tests above assert on unix.
def test_docker_env_empty_on_windows [] {
	print "test docker-env is empty on windows..."
	let fx = (setup-fixture)
	let out = (do {
		nu -c $"use ($fx.distro)/auto-bayt.nu docker-env; docker-env | to nuon"
	} | complete)
	assert ($out.exit_code == 0) $"expected 0, got ($out.exit_code): ($out.stderr)"
	assert (($out.stdout | str trim) == "{}") $"expected empty docker-env, got: ($out.stdout)"
	rm -rf $fx.tmpdir
	print "  ok\n"
}

# docker-env is the exported seam the root .justfile generate-all recipe
# wires; on unix it must yield a DOCKER_CONFIG whose shim passes the same
# checks as the rule path.
def test_docker_env_export [] {
	print "test docker-env export yields a pinned DOCKER_CONFIG..."
	let fx = (setup-fixture)
	let out = (do {
		nu -c $"use ($fx.distro)/auto-bayt.nu docker-env; docker-env | get DOCKER_CONFIG"
	} | complete)
	assert ($out.exit_code == 0) $"expected 0, got ($out.exit_code): ($out.stderr)"
	$out.stdout | str trim | save -f ($fx.tmpdir | path join "dockercfg")
	assert-pinned-shim $fx
	rm -rf $fx.tmpdir
}

# The recorded DOCKER_CONFIG must exist and its docker-compose shim must
# be an executable that routes through a mise tool-stub to the distro's
# compose stub — an executable alone could be the host's real plugin.
def assert-pinned-shim [fx: record] {
	let cfg = (open ($fx.tmpdir | path join "dockercfg") | str trim)
	assert ($cfg | is-not-empty) "expected DOCKER_CONFIG to be set for the generator"
	let shim = ($cfg | path join "cli-plugins" "docker-compose")
	assert ($shim | path exists) $"expected compose shim at ($shim)"
	let mode = (ls -l $shim | first | get mode)
	assert ($mode | str contains "x") $"expected executable shim, mode: ($mode)"
	let body = (open $shim)
	assert ($body | str contains "tool-stub") $"expected tool-stub invocation in shim: ($body)"
	assert ($body | str contains ($fx.distro | path join "compose")) $"expected distro compose stub path in shim: ($body)"
}
