use std/assert

const source = (path self | path dirname)

def invoke [fixture: path]: nothing -> record {
	do { ^nu ($source | path join "sayt.nu") -d $fixture verify } | complete
}

def main [] {
	let fixture = mktemp -d
	mkdir ($fixture | path join ".bayt")
	{say: {verify: {do: "print GENERATED_VERIFY"}}} | to yaml | save ($fixture | path join ".bayt/say.yaml")
	'package say
say: verify: keep_going: false
' | save ($fixture | path join ".say.cue")
	let implicit = invoke $fixture
	assert equal $implicit.exit_code 0 $implicit.stderr
	assert not ($implicit.stdout | str contains "GENERATED_VERIFY") $implicit.stdout
	cp ($fixture | path join ".bayt/say.yaml") ($fixture | path join ".say.yaml")
	let composed = invoke $fixture
	assert equal $composed.exit_code 0 $composed.stderr
	assert ($composed.stdout | str contains "GENERATED_VERIFY") $composed.stdout
	'package say
say: verify: do: "print AUTHORED_VERIFY"
' | save -f ($fixture | path join ".say.cue")
	let conflict = invoke $fixture
	assert ($conflict.exit_code != 0) $conflict.stdout
	assert ($conflict.stderr | str contains "conflicting values") $conflict.stderr
	let selected = (do {
		cd $fixture
		^nu -c $"use ($source)/config.nu [load-config]; load-config --config .say.yaml | to json --raw"
	} | complete)
	assert equal $selected.exit_code 0 $selected.stderr
	assert equal ($selected.stdout | from json | get say.verify.do) "print GENERATED_VERIFY"
	{say: {verify: {do: "print NESTED_CHECK"}}} | to yaml | save ($fixture | path join ".bayt/checks.yaml")
	let nested = (do {
		cd $fixture
		^nu -c $"use ($source)/config.nu [load-config]; load-config --config .bayt/checks.yaml | to json --raw"
	} | complete)
	assert equal $nested.exit_code 0 $nested.stderr
	assert equal ($nested.stdout | from json | get say.verify.do) "print NESTED_CHECK"

	'package say
say: verify: keep_going: false
' | save -f ($fixture | path join ".say.cue")
	{say: {verify: {do: "print AUTHORED_VERIFY"}}} | to yaml | save -f ($fixture | path join ".say.yaml")
	rm ($fixture | path join ".bayt/say.yaml")
	let legacy = invoke $fixture
	assert equal $legacy.exit_code 0 $legacy.stderr
	assert ($legacy.stdout | str contains "AUTHORED_VERIFY") $legacy.stdout
	rm -rf $fixture
	print "config_generation_test: generated configuration requires explicit glue and selectors stay isolated"
}
