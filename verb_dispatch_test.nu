#!/usr/bin/env nu
# Tests for verb dispatch: config overrides, script overrides, parameter flow
# Run with: nu verb_dispatch_test.nu (from plugins/sayt directory)

use std/assert

def main [] {
	print "Running verb dispatch tests...\n"

	test_verify_default_is_nop
	test_simple_do_override
	test_script_override_via_sayt_verb_nu
	test_script_override_via_sayt_nu_with_verb
	test_sayt_nu_without_verb_falls_through
	test_single_cmd_passes_args_as_passthrough
	test_sayt_nu_can_import_sayt_modules
	test_failing_do_propagates_exit_code
	test_passing_do_exits_zero
	test_failing_do_stops_subsequent_cmds

	print "\nAll verb dispatch tests passed!"
}

def make-test-dir [] {
	let tmpdir = (mktemp -d)
	# Copy config.cue so load-config can find it via FILE_PWD resolution
	# The test runs sayt.nu which sets FILE_PWD to its own directory,
	# so config.cue is already found. We just need the tmpdir for -d flag.
	$tmpdir
}

def test_verify_default_is_nop [] {
	print "test verify with no config is a nop (exit 0)..."
	let tmpdir = (make-test-dir)
	# verify should succeed silently — no skaffold.yaml required
	let result = (do { nu sayt.nu -d $tmpdir verify } | complete)
	assert ($result.exit_code == 0) $"verify should exit 0 as nop, got exit code ($result.exit_code): ($result.stderr)"
	rm -rf $tmpdir
}

def test_simple_do_override [] {
	print "test say.verify custom rule overrides builtin..."
	let tmpdir = (make-test-dir)
	# Add a custom rule with higher priority (-1 < 0) so it runs before builtin
	'say:
  verify:
    rulemap:
      custom:
        priority: -1
        cmds:
          - do: "echo CUSTOM_VERIFY"
' | save ($tmpdir | path join ".say.yaml")
	let result = (do { nu sayt.nu -d $tmpdir verify } | complete)
	assert ($result.stdout | str contains "CUSTOM_VERIFY") $"expected CUSTOM_VERIFY in output, got: ($result.stdout)"
	rm -rf $tmpdir
}

def test_script_override_via_sayt_verb_nu [] {
	print "test .sayt.verify.nu overrides verify..."
	let tmpdir = (make-test-dir)
	'def --wrapped main [...args] { let a = ($args | str join " "); print $"SCRIPT_VERIFY ($a)" }
' | save ($tmpdir | path join ".sayt.verify.nu")
	let result = (do { nu sayt.nu -d $tmpdir verify --flag1 } | complete)
	assert ($result.stdout | str contains "SCRIPT_VERIFY") $"expected SCRIPT_VERIFY, got: ($result.stdout)($result.stderr)"
	assert ($result.stdout | str contains "--flag1") $"expected --flag1 passthrough, got: ($result.stdout)"
	rm -rf $tmpdir
}

def test_script_override_via_sayt_nu_with_verb [] {
	print "test .sayt.nu with 'main verify' overrides verify..."
	let tmpdir = (make-test-dir)
	'def main [] {}
export def --wrapped "main verify" [...args] { let a = ($args | str join " "); print $"SAYT_NU_VERIFY ($a)" }
export def "main build" [...args] { print "SAYT_NU_BUILD" }
' | save ($tmpdir | path join ".sayt.nu")
	let result = (do { nu sayt.nu -d $tmpdir verify --extra-flag } | complete)
	assert ($result.stdout | str contains "SAYT_NU_VERIFY") $"expected SAYT_NU_VERIFY, got: ($result.stdout)($result.stderr)"
	assert ($result.stdout | str contains "--extra-flag") $"expected --extra-flag passthrough, got: ($result.stdout)"
	rm -rf $tmpdir
}

def test_sayt_nu_without_verb_falls_through [] {
	print "test .sayt.nu without 'main verify' falls through to config/builtin..."
	let tmpdir = (make-test-dir)
	# .sayt.nu defines build but NOT verify
	'def main [] {}
export def "main build" [...args] { print "SAYT_NU_BUILD" }
' | save ($tmpdir | path join ".sayt.nu")
	# verify should still work (nop default), not error
	let result = (do { nu sayt.nu -d $tmpdir verify } | complete)
	assert ($result.exit_code == 0) $"verify should fall through to nop, got: ($result.exit_code) ($result.stderr)"
	rm -rf $tmpdir
}

def test_single_cmd_passes_args_as_passthrough [] {
	print "test single-cmd rule appends args to command..."
	let tmpdir = (make-test-dir)
	# Add a custom rule with higher priority so it runs before builtin
	'say:
  verify:
    rulemap:
      custom:
        priority: -1
        cmds:
          - do: "echo VERIFY_WITH"
' | save ($tmpdir | path join ".say.yaml")
	let result = (do { nu sayt.nu -d $tmpdir verify --extra } | complete)
	assert ($result.stdout | str contains "VERIFY_WITH") $"expected VERIFY_WITH, got: ($result.stdout)"
	# Args should be appended to the echo command
	assert ($result.stdout | str contains "--extra") $"expected --extra appended, got: ($result.stdout)"
	rm -rf $tmpdir
}

def test_failing_do_propagates_exit_code [] {
	print "test a failing verb cmd propagates its non-zero exit..."
	let tmpdir = (make-test-dir)
	# A lint/build that always exits 0 is worse than none. A `do:` whose
	# command fails MUST fail the verb — nushell does not `set -e`, so
	# run-verb has to check LAST_EXIT_CODE explicitly.
	'say:
  verify:
    rulemap:
      custom:
        priority: -1
        cmds:
          - do: "^sh -c \"exit 5\""
' | save ($tmpdir | path join ".say.yaml")
	let result = (do { nu sayt.nu -d $tmpdir verify } | complete)
	assert ($result.exit_code == 5) $"failing do must propagate exit 5, got: ($result.exit_code)"
	rm -rf $tmpdir
}

def test_passing_do_exits_zero [] {
	print "test a passing verb cmd still exits 0 (no false failures)..."
	let tmpdir = (make-test-dir)
	'say:
  verify:
    rulemap:
      custom:
        priority: -1
        cmds:
          - do: "^sh -c true"
' | save ($tmpdir | path join ".say.yaml")
	let result = (do { nu sayt.nu -d $tmpdir verify } | complete)
	assert ($result.exit_code == 0) $"passing do must exit 0, got: ($result.exit_code) ($result.stderr)"
	rm -rf $tmpdir
}

def test_failing_do_stops_subsequent_cmds [] {
	print "test fail-fast: a failing cmd stops later cmds in the rule..."
	let tmpdir = (make-test-dir)
	# First cmd fails; the second must never run (fail-fast).
	'say:
  verify:
    rulemap:
      custom:
        priority: -1
        cmds:
          - do: "^sh -c \"exit 4\""
          - do: "^sh -c \"touch should-not-exist\""
' | save ($tmpdir | path join ".say.yaml")
	let result = (do { nu sayt.nu -d $tmpdir verify } | complete)
	assert ($result.exit_code == 4) $"first-cmd failure must propagate exit 4, got: ($result.exit_code)"
	assert (not ($tmpdir | path join "should-not-exist" | path exists)) "second cmd ran despite the first failing — not fail-fast"
	rm -rf $tmpdir
}

def test_sayt_nu_can_import_sayt_modules [] {
	print "test .sayt.nu can import tools.nu from sayt..."
	let tmpdir = (make-test-dir)
	# Create a .sayt.nu that imports tools.nu (from sayt's directory)
	'use tools.nu
def main [] {}
export def "main verify" [...args] { print "TOOLS_IMPORTED_OK" }
' | save ($tmpdir | path join ".sayt.nu")
	let result = (do { nu sayt.nu -d $tmpdir verify } | complete)
	assert ($result.exit_code == 0) $"should succeed, got: ($result.exit_code) ($result.stderr)"
	assert ($result.stdout | str contains "TOOLS_IMPORTED_OK") $"expected TOOLS_IMPORTED_OK, got: ($result.stdout)"
	rm -rf $tmpdir
}
