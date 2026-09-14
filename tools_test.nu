use std/assert

const path_self = path self

def run-vrun [call: string]: nothing -> record {
	let tools = ($path_self | path dirname | path join tools.nu)
	^$nu.current-exe -c $"use ($tools) [vrun]; ($call)" | complete
}

# A mise `[env]` `exec()` takes stdout whole: a diagnostic printed ahead of the
# value became part of the variable.
def test_vrun_stdout_is_the_command_output_alone [] {
	let r = (run-vrun "vrun --envs {FOO: bar} echo hi")
	assert equal ($r.stdout | str trim) "hi" $"stdout carried more than the command: ($r.stdout)"
}

def test_vrun_diagnostics_go_to_stderr [] {
	let r = (run-vrun "vrun --envs {FOO: bar} echo hi")
	# Spans both export syntaxes: `export FOO=bar` and Windows' `$env:FOO = bar`.
	assert ($r.stderr =~ 'FOO\s*=\s*bar') $"export preamble missing from stderr: ($r.stderr)"
	assert ($r.stderr | str contains "echo hi") $"command echo missing from stderr: ($r.stderr)"
}

def test_vrun_redacts_secrets_wherever_it_prints [] {
	let r = (run-vrun "vrun --envs {MY_TOKEN: s3cr3t} echo hi")
	assert ($r.stderr | str contains "***redacted***") $"secret was not redacted: ($r.stderr)"
	assert (not ($"($r.stdout)($r.stderr)" | str contains "s3cr3t")) "the secret's value reached the output"
}

def fake-mise []: nothing -> record {
	let root = mktemp -d
	let bin = $root | path join "private tools"
	mkdir $bin
	let script = $bin | path join "fake.nu"
	' def --wrapped main [...args] {
		print ({args: $args, locked: $env.MISE_LOCKED?, mise: $env.SAYT_MISE_BIN, found: (which mise | first | get path), bake: $env.COMPOSE_BAKE?} | to json)
		if "__fail__" in $args { exit 23 }
	}' | save $script
	let windows = $nu.os-info.name == "windows"
	let exe = $bin | path join (if $windows { "mise.cmd" } else { "mise" })
	if $windows {
		$"@echo off\r\n\"($nu.current-exe)\" --no-config-file \"($script)\" %*\r\n" | save $exe
	} else {
		$"#!/bin/sh\nexec '($nu.current-exe)' --no-config-file '($script)' \"$@\"\n" | save $exe
		^chmod +x $exe
	}
	{root: $root, exe: $exe}
}

def --wrapped run-tool [fx: record, ...args]: nothing -> record {
	let tools = $path_self | path dirname | path join "tools.nu"
	do {
		cd $fx.root
		with-env {SAYT_MISE_BIN: $fx.exe, MISE_LOCKED: "0"} {
			^$nu.current-exe --no-config-file $tools ...$args
		}
	} | complete
}

def test_dispatch_preserves_stub_pins_and_arguments [] {
	let fx = fake-mise
	for tool in [cue docker compose git-cliff goreleaser nu] {
		let r = run-tool $fx $tool "two words" --flag "a'b" ""
		assert equal $r.exit_code 0 $r.stderr
		let observed = $r.stdout | from json
		assert equal $observed.args.0 "tool-stub"
		assert (($observed.args.1 | path basename) in [$"($tool).toml" $"($tool).musl.toml"])
		assert equal ($observed.args | skip 2) ["two words" "--flag" "a'b" ""]
		assert equal $observed.locked "0"
		assert equal $observed.mise $fx.exe
		assert equal $observed.found $fx.exe
		if $tool == "compose" { assert equal $observed.bake "true" }
	}
	rm -rf $fx.root
}

# A wrapper's stub unlock must not weaken later project installs or execution.
def test_project_operations_restore_config_locking [] {
	let fx = fake-mise
	for args in [[install] [exec -- deno --version]] {
		let r = run-tool $fx mise ...$args
		assert equal $r.exit_code 0 $r.stderr
		let observed = $r.stdout | from json
		assert equal $observed.args $args
		assert equal $observed.locked null
		assert equal $observed.found $fx.exe
	}
	let r = run-tool $fx mise lock --platform linux-x64
	assert equal $r.exit_code 0 $r.stderr
	assert equal ($r.stdout | from json | get locked) "0"
	rm -rf $fx.root
}

def test_dispatch_preserves_failure_and_rejects_unknown_tools [] {
	let fx = fake-mise
	let failed = run-tool $fx cue __fail__
	assert equal $failed.exit_code 23
	let unsupported = run-tool $fx arbitrary __fail__
	assert ($unsupported.exit_code != 0)
	assert equal $unsupported.stdout ""
	assert ($unsupported.stderr | str contains "unsupported tool arbitrary")
	rm -rf $fx.root
}

def main [] {
	test_vrun_stdout_is_the_command_output_alone
	test_vrun_diagnostics_go_to_stderr
	test_vrun_redacts_secrets_wherever_it_prints
	test_dispatch_preserves_stub_pins_and_arguments
	test_project_operations_restore_config_locking
	test_dispatch_preserves_failure_and_rejects_unknown_tools
	print "tools_test: all passed"
}
