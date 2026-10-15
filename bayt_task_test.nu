use std/assert

const source = (path self | path dirname)
const fingerprint = (path self | path dirname | path join "../bayt/runtime/fingerprint.nu" | path expand)

def main [] {
	# These read a rule's output to tell which rule ran; below verbose it goes to a log.
	$env.SAYT_VERBOSITY = "verbose"
	let fixture = mktemp -d --tmpdir-path $source
	mkdir ($fixture | path join ".bayt")
	{version: "3", tasks: {"bayt:generate": {dir: "..", cmds: ["nu generate.nu"]}, "bayt:action": {dir: "..", cmds: ["echo OLD_GRAPH"]}}} | to yaml | save ($fixture | path join ".bayt/Taskfile.yml")
	{version: "3", tasks: {"bayt:generate": {dir: "..", cmds: ["nu generate.nu"]}, "bayt:action": {dir: "..", cmds: ["echo NEW_GRAPH"]}}} | to yaml | save ($fixture | path join "next.yaml")
	'cp next.yaml .bayt/Taskfile.yml' | save ($fixture | path join "generate.nu")
	let result = (do {
		cd $fixture
		^nu -c $"use ($source)/bayt-task.nu; bayt-task action --generate"
	} | complete)
	assert equal $result.exit_code 0 $result.stderr
	assert ($result.stdout | str contains "NEW_GRAPH") $result.stdout
	assert not ($result.stdout | str contains "OLD_GRAPH") $result.stdout
	{say: {build: {do: "print BUILD_LEAF"}, test: {args: "default-value", do: "print LEAF"}}} | to yaml | save ($fixture | path join ".bayt/checks.yaml")
	{version: "3", tasks: {"bayt:build": {dir: "..", cmds: [$'nu -c "use ($source)/task-leaf.nu; task-leaf build"']}, "bayt:test": {dir: "..", deps: ["bayt:build"], cmds: [$'nu -c "use ($source)/task-leaf.nu; task-leaf test"']}}} | to yaml | save -f ($fixture | path join ".bayt/Taskfile.yml")
	let defaults = (do { cd $fixture; ^nu -c $"use ($source)/bayt-task.nu; bayt-task test" } | complete)
	assert equal $defaults.exit_code 0 $defaults.stderr
	assert ($defaults.stdout | str contains "default-value") $defaults.stdout
	let explicit = (do { cd $fixture; ^nu -c $"use ($source)/bayt-task.nu; bayt-task test override-value" } | complete)
	let platform = (do {
		cd $fixture
		{say: {build: {do: "print BUILD_LEAF"}, test: {rulemap: {other: {platform: "other", stop: true, cmds: [{do: "print OTHER_PLATFORM"}]}}}}} | to yaml | save -f .bayt/checks.yaml
		with-env {SAYT_PLATFORM: "other"} { ^nu -c $"use ($source)/bayt-task.nu; bayt-task test" }
	} | complete)
	assert equal $platform.exit_code 0 $platform.stderr
	assert ($platform.stdout | str contains "OTHER_PLATFORM") $platform.stdout
	rm -rf $fixture
	assert equal $explicit.exit_code 0 $explicit.stderr
	assert ($explicit.stdout | str contains "override-value") $explicit.stdout
	assert equal ($explicit.stdout | split row "override-value" | length) 2 $explicit.stdout
	assert not ($explicit.stdout | str contains "default-value") $explicit.stdout
	test_cached_invocations
	test_missing_checks
	test_repairs_checks
	test_generation_uses_refreshed_rules
}

def test_cached_invocations [] {
	let fixture = mktemp -d --tmpdir-path $source
	mkdir ($fixture | path join ".bayt")
	{say: {test: {do: "print LEAF", rulemap: {other: {platform: "other", stop: true, cmds: [{do: "print OTHER"}]}}}}} | to yaml | save ($fixture | path join ".bayt/checks.yaml")
	{name: "test", dir: "", srcs: {globs: [".bayt/checks.yaml"], exclude: []}, outs: {globs: [], exclude: []}, state: {globs: []}, chainedDeps: [], cmds: []} | to json | save ($fixture | path join ".bayt/bayt.test.json")
	let status = $"nu '($fingerprint)' --manifest .bayt/bayt.test.json --stamp-file .task/test.hash"
	{version: "3", tasks: {"bayt:test": {dir: "..", status: [$status], cmds: [$'nu -c "use ($source)/task-leaf.nu; task-leaf test"', {defer: $"($status) --update-stamp"}]}}} | to yaml | save ($fixture | path join ".bayt/Taskfile.yml")
	let first = (do { cd $fixture; ^nu -c $"use ($source)/bayt-task.nu; bayt-task test first" } | complete)
	let changed = (do { cd $fixture; ^nu -c $"use ($source)/bayt-task.nu; bayt-task test second" } | complete)
	let warm = (do { cd $fixture; ^nu -c $"use ($source)/bayt-task.nu; bayt-task test second" } | complete)
	let platform = (do { cd $fixture; with-env {SAYT_PLATFORM: "other"} { ^nu -c $"use ($source)/bayt-task.nu; bayt-task test second" } } | complete)
	rm -rf $fixture
	for result in [$first $changed $warm $platform] { assert equal $result.exit_code 0 $result.stderr }
	assert ($first.stdout | str contains "first") $first.stdout
	assert ($changed.stdout | str contains "second") $changed.stdout
	assert ($warm.stderr | str contains "up to date") $warm.stderr
	assert ($platform.stdout | str contains "OTHER") $platform.stdout
}

def test_missing_checks [] {
	let fixture = mktemp -d --tmpdir-path $source
	let result = (do { cd $fixture; ^nu -c $"use ($source)/task-leaf.nu; task-leaf test" } | complete)
	rm -rf $fixture
	assert not equal $result.exit_code 0
	assert ($result.stderr | str contains "missing .bayt/checks.yaml") $result.stderr
}

def test_repairs_checks [] {
	let fixture = mktemp -d --tmpdir-path $source
	let leaf = $'nu -c "use ($source)/task-leaf.nu; task-leaf test"'
	{
		name: ($fixture | path basename), dir: ".", activate: ""
		files: {"checks.yaml": {say: {test: {do: "print REPAIRED"}}}}
		targets: {test: {taskfile: {incremental: false}, cmd: {builtin: {shell: "exec", do: $leaf}}}}
	} | to json | save ($fixture | path join "bayt.json")
	'@extern(embed)
package fixture
import bayt "bonisoft.org/plugins/bayt/core:bayt"
data: _ @embed(file="bayt.json")
project: bayt.#project & data
depManifestsIn: {[string]: _}
_render: bayt.#render & {project: project, depManifests: depManifestsIn}
' | save ($fixture | path join "bayt.cue")
	let first = (do { cd $fixture; ^nu -c $"use ($source)/bayt-task.nu; bayt-task test" } | complete)
	assert equal $first.exit_code 0 $first.stderr
	rm ($fixture | path join ".bayt/checks.yaml")
	let repaired = (do { cd $fixture; ^nu -c $"use ($source)/bayt-task.nu; bayt-task test" } | complete)
	rm -rf $fixture
	assert equal $repaired.exit_code 0 $repaired.stderr
	assert ($repaired.stdout | str contains "REPAIRED") $repaired.stdout
}

def test_generation_uses_refreshed_rules [] {
	let fixture = mktemp -d --tmpdir-path $source
	mkdir ($fixture | path join ".bayt")
	let rules = {"auto-cue": null, "auto-gomplate": null, "auto-bayt": null, builtin: {stop: false, cmds: [{do: "cp next.yaml .bayt/checks.yaml"}]}}
	{say: {generate: {rulemap: $rules}}} | to yaml | save ($fixture | path join ".bayt/checks.yaml")
	{say: {generate: {rulemap: ($rules | insert added {priority: 3, cmds: [{do: "print FRESH_GENERATOR"}]})}}} | to yaml | save ($fixture | path join "next.yaml")
	let result = (do { cd $fixture; ^nu -c $"use ($source)/task-leaf.nu; task-leaf generate" } | complete)
	rm -rf $fixture
	assert equal $result.exit_code 0 $result.stderr
	assert ($result.stdout | str contains "FRESH_GENERATOR") $result.stdout
}
