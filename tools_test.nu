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
		# mise names it Path on Windows, where a PATH lookup failed every release.
		let path_key = if $nu.os-info.name == "windows" { "Path" } else { "PATH" }
		if $args.0? == "env" { print ({} | insert $path_key ($env.PATH | str join (char esep)) | to json); return }
		if $args.0? == "which" { print $env.SAYT_MISE_BIN; return }
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
		if $tool == "goreleaser" {
			assert equal $observed.args ["two words" "--flag" "a'b" ""]
			assert ($r.stderr | str contains "which goreleaser --tool http:goreleaser")
		} else {
			assert equal $observed.args.0 "tool-stub"
			assert (($observed.args.1 | path basename) in [$"($tool).toml" $"($tool).musl.toml"])
			assert equal ($observed.args | skip 2) ["two words" "--flag" "a'b" ""]
			assert equal $observed.locked "0"
		}
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

def cached-mise [caches: list<string>]: nothing -> record {
	let home = (mktemp -d)
	let exe = if $nu.os-info.name == "windows" { "mise.exe" } else { "mise" }
	let pinned = (open --raw ($path_self | path dirname | path join sayt.sh) | parse -r 'MISE_VERSION="(?<v>[^"]+)"' | get 0.v)
	for cache in ($caches | each { |c| $home | path join $c }) {
		for v in [v2026.5.2 $pinned v2026.99.0] {
			mkdir ($cache | path join $"mise-($v)")
			touch ($cache | path join $"mise-($v)" $exe)
		}
	}
	let tools = ($path_self | path dirname | path join tools.nu)
	let r = (with-env {HOME: $home, XDG_CACHE_HOME: ($home | path join .cache), LOCALAPPDATA: $home} {
		^$nu.current-exe -c $"hide-env -i SAYT_MISE_BIN; use ($tools) [mise-bin]; mise-bin" | complete
	})
	rm -rf $home
	{r: $r, pinned: $"mise-($pinned)"}
}

# Without a launcher's SAYT_MISE_BIN, the launchers' pinned mise runs. Taking
# the newest cached one kept a CI cache's v2026.10.1 after the pin went back to
# v2026.8.11.
def test_cache_fallback_takes_the_pinned_mise [] {
	let got = (cached-mise [(["Library" "Caches" "sayt"] | path join) (".cache" | path join sayt) "sayt"])
	assert equal $got.r.exit_code 0 $got.r.stderr
	assert equal ($got.r.stdout | str trim | path dirname | path basename) $got.pinned
}

# sayt.sh caches under XDG's dir on macOS too, where sayt.zig uses
# ~/Library/Caches; a fallback that searched only the latter missed sayt.sh's.
def test_cache_fallback_finds_sayt_sh_cache_on_macos [] {
	if (uname | get kernel-name) != "Darwin" { return }
	let got = (cached-mise [(".cache" | path join sayt)])
	assert equal $got.r.exit_code 0 $got.r.stderr
	assert equal ($got.r.stdout | str trim | path dirname | path basename) $got.pinned
}

def run-live-as [level: string, call: string]: nothing -> record {
	let tools = ($path_self | path dirname | path join tools.nu)
	let logs = (mktemp -d -t sayt-test.XXXXXX)
	let r = (with-env {SAYT_VERBOSITY: $level, SAYT_LOG_DIR: $logs, SAYT_HEARTBEAT_SECS: "1"} {
		^$nu.current-exe -c $"use ($tools) [run-live vrun-live vrun note]; exit \(($call)\)" | complete
	})
	$r | insert logs $logs
}

# The logs a run left. Listed, not globbed: a glob built from a Windows path
# reads its backslashes as escapes.
def logs-in [dir: string] {
	ls $dir | where name ends-with ".log" | get name
}

const fifty = "run-live nu -c 'for i in 1..50 { print $\"line ($i)\" }'"
const failing = "run-live nu -c 'for i in 1..80 { print $\"line ($i)\" }; exit 3'"

# An agent reads a tool call's whole output as context: a build log streamed
# into it cost ~12k tokens per integrate. Normal keeps the command and verdict
# and moves the output into a log the verdict points at.
def test_normal_success_prints_a_verdict_not_the_output [] {
	let r = (run-live-as normal $fifty)
	assert equal $r.exit_code 0
	assert not ($r.stdout + $r.stderr | str contains "line 50") $"normal printed the output: ($r.stderr)"
	assert ($r.stderr =~ '✓ nu .*50 lines.*log: ') $"verdict missing: ($r.stderr)"
	assert (open --raw (logs-in $r.logs | first) | str contains "line 50") "the log lost the output"
}

def test_quiet_success_prints_nothing [] {
	let r = (run-live-as quiet $fifty)
	assert equal $r.exit_code 0
	assert equal ($r.stdout + $r.stderr | str trim) "" $"quiet printed: ($r.stderr)"
}

# A 40-line tail of a failed bake was BuildKit's Dockerfile excerpt and
# compose's teardown; the visual gate's findings sat a screen above it.
def test_failure_prints_the_whole_log_and_passes_the_exit_code_through [] {
	for level in [normal quiet] {
		let r = (run-live-as $level $failing)
		assert equal $r.exit_code 3
		assert (($r.stdout | lines | first) == "line 1") $"($level) log missing its start: ($r.stdout)"
		assert ($r.stdout | str contains "line 80") $"($level) log missing its end: ($r.stdout)"
		assert ($r.stderr =~ '✗ nu .*exit 3.*log: ') $"($level) verdict missing: ($r.stderr)"
	}
}

# A silent tool call reads as a hang, and some agent harnesses kill one.
def test_normal_heartbeats_while_a_command_runs [] {
	let r = (run-live-as normal "run-live nu -c 'sleep 2.5sec'")
	assert ($r.stderr | str contains "still running") $"no heartbeat: ($r.stderr)"
	let q = (run-live-as quiet "run-live nu -c 'sleep 2.5sec'")
	assert not ($q.stderr | str contains "still running") "quiet heartbeated"
}

def test_vrun_live_keeps_the_redacted_preamble [] {
	let r = (run-live-as normal "vrun-live --envs {MY_TOKEN: s3cret} nu -c 'print hi'")
	assert equal $r.exit_code 0
	assert not ($r.stderr | str contains "s3cret") "a secret reached the preamble"
	assert ($r.stderr =~ 'MY_TOKEN.*redacted') $"preamble missing: ($r.stderr)"
	let q = (run-live-as quiet "vrun-live --envs {MY_TOKEN: s3cret} nu -c 'print hi'")
	assert equal ($q.stdout + $q.stderr | str trim) "" $"quiet printed the preamble: ($q.stderr)"
}

# vrun's callers capture its stdout as data; quiet drops only the chatter around it.
def test_quiet_keeps_vrun_output_and_drops_its_preamble_and_notes [] {
	let call = "vrun nu -c 'print data'; note step; 0"
	let n = (run-live-as normal $call)
	assert ($n.stderr =~ "nu -c .*\nstep") $"normal lost the preamble or note: ($n.stderr)"
	let q = (run-live-as quiet $call)
	assert equal ($q.stdout | str trim) "data"
	assert equal ($q.stderr | str trim) "" $"quiet printed: ($q.stderr)"
}

# A verdict names the tool under mise and skips flags and their values: it
# read `mise exec --` for every bayt task, whatever failed.
def test_verdict_names_the_tool_under_mise [] {
	let bin = (mktemp -d -t sayt-mise.XXXXXX)
	# A mise that runs nothing: the verdict's name is read from the words.
	let mise = if $nu.os-info.name == "windows" {
		let exe = $bin | path join mise.cmd
		"@exit /b 0\r\n" | save $exe
		$exe
	} else {
		let exe = $bin | path join mise
		"#!/bin/sh\nexit 0\n" | save $exe
		^chmod +x $exe
		$exe
	}
	let r = (run-live-as normal $"run-live '($mise)' exec -- sh -c 'exit 0' bayt:test")
	assert ($r.stderr =~ '✓ sh bayt:test \(') $"wrong name: ($r.stderr)"
	# A wrapper with nothing after it names itself rather than failing the command.
	let bare = (run-live-as normal $"run-live '($mise)' exec")
	assert ($bare.stderr =~ '(✓|✗) mise exec') $"a bare wrapper broke naming: ($bare.stderr)"
}

def test_verbose_streams_and_keeps_no_log [] {
	let r = (run-live-as verbose "run-live nu -c 'print streamed'")
	assert equal $r.exit_code 0
	assert ($r.stdout | str contains "streamed") $"verbose did not stream: ($r)"
	assert equal (logs-in $r.logs | length) 0 "verbose wrote a log"
}

# Unset, a terminal or CI is verbose and an agent's pipe is normal.
def test_default_level_follows_the_terminal_and_ci [] {
	let tools = ($path_self | path dirname | path join tools.nu)
	let piped = (with-env {SAYT_VERBOSITY: ""} { hide-env -i CI; ^$nu.current-exe -c $"use ($tools) [verbosity]; verbosity" | complete })
	assert equal ($piped.stdout | str trim) "normal"
	let ci = (with-env {SAYT_VERBOSITY: "", CI: "true"} { ^$nu.current-exe -c $"use ($tools) [verbosity]; verbosity" | complete })
	assert equal ($ci.stdout | str trim) "verbose"
}

def main [] {
	test_normal_success_prints_a_verdict_not_the_output
	test_quiet_success_prints_nothing
	test_failure_prints_the_whole_log_and_passes_the_exit_code_through
	test_normal_heartbeats_while_a_command_runs
	test_vrun_live_keeps_the_redacted_preamble
	test_quiet_keeps_vrun_output_and_drops_its_preamble_and_notes
	test_verdict_names_the_tool_under_mise
	test_verbose_streams_and_keeps_no_log
	test_default_level_follows_the_terminal_and_ci
	test_cache_fallback_takes_the_pinned_mise
	test_cache_fallback_finds_sayt_sh_cache_on_macos
	test_vrun_stdout_is_the_command_output_alone
	test_vrun_diagnostics_go_to_stderr
	test_vrun_redacts_secrets_wherever_it_prints
	test_dispatch_preserves_stub_pins_and_arguments
	test_project_operations_restore_config_locking
	test_dispatch_preserves_failure_and_rejects_unknown_tools
	print "tools_test: all passed"
}
