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

def main [] {
	test_vrun_stdout_is_the_command_output_alone
	test_vrun_diagnostics_go_to_stderr
	test_vrun_redacts_secrets_wherever_it_prints
	print "tools_test: all passed"
}
