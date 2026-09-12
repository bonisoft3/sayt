#!/usr/bin/env nu
# Tests for auto-terminal.nu layout detection.
# Run with: nu auto_terminal_test.nu (from plugins/sayt directory)

use std/assert

def main [] {
	print "Running auto-terminal tests...\n"

	test_external_layout_uses_path_omnishell
	test_sibling_layout_names_the_checkout
	test_nop_without_program_cue

	print "\nAll auto-terminal tests passed!"
}

# The stanza a fake omnishell prints, so the rule's own writing is what the
# assertions read.
const _stanza = "package fixture\n\nterminal: surface: runtime: \"stated\""

# PATH lookup on Windows executes only known extensions, so a fake named
# `omnishell` with a shebang is invisible there.
def install-fake [entry: path, sink: path] {
	if $nu.os-info.name == "windows" {
		$"@echo off\r\necho FAKE_OMNISHELL %* > \"($sink)\"\r\necho package fixture\r\necho.\r\necho terminal: surface: runtime: \"stated\"\r\n" | save -f $"($entry).cmd"
	} else {
		$"#!/bin/sh\necho \"FAKE_OMNISHELL $@\" > ($sink)\ncat <<'EOF'\n($_stanza)\nEOF\n" | save -f $entry
		^chmod +x $entry
	}
}

# Shared fixture: copied sayt distro, a bin dir for fakes, and a project
# dir (with program.cue unless --no-program-cue).
def setup-fixture [--no-program-cue]: nothing -> record {
	let tmpdir = (mktemp -d)
	let distro = ($tmpdir | path join "sayt")
	mkdir $distro
	cp auto-terminal.nu $distro
	let bin = ($tmpdir | path join "bin")
	mkdir $bin
	let proj = ($tmpdir | path join "proj")
	mkdir $proj
	if not $no_program_cue {
		"package fixture" | save ($proj | path join "program.cue")
	}
	{tmpdir: $tmpdir, distro: $distro, bin: $bin, proj: $proj}
}

def run-auto-terminal [fx: record]: nothing -> record {
	let searched = ([$fx.bin] ++ $env.PATH)
	# Windows command search reads `Path`, and nushell 0.115 folds env-var case;
	# hand the child one canonical `Path`, joined to a string here so nothing
	# has to reconvert a list before `^omnishell` resolves.
	let injected = if $nu.os-info.name == "windows" {
		{Path: ($searched | str join (char esep))}
	} else {
		{PATH: $searched}
	}
	do {
		cd $fx.proj
		with-env $injected {
			nu -c $"use ($fx.distro)/auto-terminal.nu; auto-terminal"
		}
	} | complete
}

def written [fx: record]: nothing -> string {
	let out = ($fx.proj | path join "program_terminal.cue")
	assert ($out | path exists) $"expected a stanza at ($out)"
	open --raw $out | str trim
}

# Without a sibling omnishell checkout (mise http-tarball layout), the project
# is answered by the `omnishell` on PATH, and names it by the bare token.
def test_external_layout_uses_path_omnishell [] {
	print "test external layout runs omnishell from PATH..."
	let fx = (setup-fixture)
	install-fake ($fx.bin | path join "omnishell") ($fx.tmpdir | path join "called")

	let result = (run-auto-terminal $fx)
	assert ($result.exit_code == 0) $"expected 0, got ($result.exit_code): ($result.stderr)"
	let called = (open ($fx.tmpdir | path join "called") | str trim)
	assert ($called == "FAKE_OMNISHELL mode .") $"expected 'FAKE_OMNISHELL mode .', got: ($called)"
	assert ((written $fx) == $_stanza) $"expected the stanza, got: (written $fx)"
	rm -rf $fx.tmpdir
}

# The sibling-checkout (monorepo) layout runs that checkout's launcher and asks
# it to name itself by a path, so the argv is pinned as exactly as the PATH
# branch's is.
def test_sibling_layout_names_the_checkout [] {
	print "test sibling layout asks the checkout to name itself..."
	let fx = (setup-fixture)
	let runtime = ($fx.tmpdir | path join "omnishell" "runtime")
	mkdir $runtime
	let entry = if $nu.os-info.name == "windows" { "omnishell.ps1" } else { "omnishell" }
	let sink = ($fx.tmpdir | path join "called")
	if $nu.os-info.name == "windows" {
		$"\"FAKE_OMNISHELL $args\" | Set-Content '($sink)'\nWrite-Output @'\n($_stanza)\n'@\n"
			| save -f ($runtime | path join $entry)
	} else {
		install-fake ($runtime | path join $entry) $sink
	}

	let result = (run-auto-terminal $fx)
	assert ($result.exit_code == 0) $"expected 0, got ($result.exit_code): ($result.stderr)"
	let called = (open $sink | str trim)
	assert ($called == "FAKE_OMNISHELL mode . --local") $"expected 'FAKE_OMNISHELL mode . --local', got: ($called)"
	assert ((written $fx) == $_stanza) $"expected the stanza, got: (written $fx)"
	rm -rf $fx.tmpdir
}

# Projects without program.cue skip the rule entirely.
def test_nop_without_program_cue [] {
	print "test nop without program.cue..."
	let fx = (setup-fixture --no-program-cue)
	install-fake ($fx.bin | path join "omnishell") ($fx.tmpdir | path join "called")

	let result = (run-auto-terminal $fx)
	assert ($result.exit_code == 0) $"expected nop exit 0, got ($result.exit_code): ($result.stderr)"
	assert (not (($fx.proj | path join "program_terminal.cue") | path exists)) "expected no stanza written"
	rm -rf $fx.tmpdir
}
