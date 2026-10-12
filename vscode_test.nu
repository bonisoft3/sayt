use std/assert

const source = (path self | path dirname)

def main [] {
	let fixture = mktemp -d
	mkdir ($fixture | path join ".vscode")
	{version: "2.0.0", tasks: [{label: "test", type: "shell", command: "echo", args: ["MODULE_PATH_OK"]}]} | to json | save ($fixture | path join ".vscode/tasks.json")
	$'use ($source)/vscode.nu [vtr]
vtr test' | save ($fixture | path join "caller.nu")
	let result = (do {
		cd $fixture
		^nu caller.nu
	} | complete)
	rm -rf $fixture
	assert equal $result.exit_code 0 $result.stderr
	assert ($result.stdout | str contains "MODULE_PATH_OK") $result.stdout
	let fixture = mktemp -d
	mkdir ($fixture | path join .vscode)
	{env: {SAYT_ENV_PROBE: "project"}} | to toml | save ($fixture | path join .mise.toml)
	{version: "2.0.0", tasks: [
		{label: "dependency", type: "shell", command: $nu.current-exe, args: ["-c", "print $env.SAYT_ENV_PROBE"], options: {env: {SAYT_ENV_PROBE: "dependency"}}},
		{label: "test", type: "shell", command: $nu.current-exe, args: ["-c", "print $env.SAYT_ENV_PROBE"], dependsOn: ["dependency"], options: {env: {SAYT_ENV_PROBE: "task"}}}
	]} | to json | save ($fixture | path join .vscode/tasks.json)
	$'use ($source)/vscode.nu [vtr]
vtr test' | save ($fixture | path join caller.nu)
	let result = (do {
		cd $fixture
		with-env {MISE_TRUSTED_CONFIG_PATHS: $fixture} { ^nu caller.nu }
	} | complete)
	rm -rf $fixture
	assert equal $result.exit_code 0 $result.stderr
	assert equal ($result.stdout | lines) [dependency task]
	if $nu.os-info.name == "windows" { return }
	let pinned = (open ($source | path join ../../.mise.toml) | get tools."github:cue-lang/cue")
	let fixture = mktemp -d
	mkdir ($fixture | path join .vscode) ($fixture | path join bin)
	{settings: {locked: true, lockfile: true, github_attestations: false, slsa: false}, tools: {"github:cue-lang/cue": $pinned}} | to toml | save ($fixture | path join .mise.toml)
	cp ($source | path join ../../mise.lock) ($fixture | path join mise.lock)
	{version: "2.0.0", tasks: [
		{label: "test", type: "shell", command: "cue", args: ["version"]},
		{label: "nested", type: "shell", command: $nu.current-exe, args: ["-c", "^cue version"]}
	]} | to json | save ($fixture | path join .vscode/tasks.json)
	"#!/bin/sh\necho AMBIENT_CUE >&2\nexit 73\n" | save ($fixture | path join bin/cue)
	^chmod +x ($fixture | path join bin/cue)
	$'use ($source)/vscode.nu [vtr]
vtr test
vtr nested' | save ($fixture | path join caller.nu)
	let result = (do {
		cd $fixture
		with-env {MISE_TRUSTED_CONFIG_PATHS: $fixture, PATH: ([($fixture | path join bin)] ++ $env.PATH)} { ^nu caller.nu }
	} | complete)
	rm -rf $fixture
	assert equal $result.exit_code 0 $result.stderr
	assert ($result.stdout | str contains $"cue version v($pinned)") $result.stdout
	assert equal ($result.stdout | lines | where {str starts-with $"cue version v($pinned)"} | length) 2
}
