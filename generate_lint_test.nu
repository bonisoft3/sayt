#!/usr/bin/env nu
# Tests for generate and lint verb dispatch through run-verb
# Covers: run-all mode, force flag, file filtering, output validation,
#         script overrides for generate/lint, multi-cmd SAYT_VERB_ARGS
# Run with: nu generate_lint_test.nu (from plugins/sayt directory)

use std/assert

def main [] {
	print "Running generate and lint verb tests...\n"

	test_generate_runs_all_rules
	test_generate_force_flag
	test_generate_file_filtering
	test_generate_output_validation_fails
	test_generate_script_override
	test_lint_runs_all_rules
	test_lint_script_override
	test_multi_cmd_passes_args_as_env

	print "\nAll generate and lint verb tests passed!"
}

def test_generate_runs_all_rules [] {
	print "test generate executes all matching rules (run-all mode)..."
	let tmpdir = (mktemp -d)
	'say:
  generate:
    rulemap:
      auto-gomplate: null
      auto-cue: null
      rule-a:
        cmds:
          - do: "print RULE_A"
      rule-b:
        cmds:
          - do: "print RULE_B"
' | save ($tmpdir | path join ".say.yaml")
	let result = (do { nu sayt.nu -d $tmpdir generate } | complete)
	assert ($result.exit_code == 0) $"generate should exit 0, got: ($result.exit_code) ($result.stderr)"
	assert ($result.stdout | str contains "RULE_A") $"expected RULE_A in output, got: ($result.stdout)"
	assert ($result.stdout | str contains "RULE_B") $"expected RULE_B in output, got: ($result.stdout)"
	rm -rf $tmpdir
}

def test_generate_force_flag [] {
	print "test generate --force sets SAY_GENERATE_ARGS_FORCE env..."
	let tmpdir = (mktemp -d)
	'say:
  generate:
    rulemap:
      auto-gomplate: null
      auto-cue: null
      check-force:
        cmds:
          - do: "print $env.SAY_GENERATE_ARGS_FORCE?"
' | save ($tmpdir | path join ".say.yaml")
	let with_force = (do { nu sayt.nu -d $tmpdir generate --force } | complete)
	assert ($with_force.stdout | str contains "true") $"expected 'true' with --force, got: ($with_force.stdout)"
	let without_force = (do { nu sayt.nu -d $tmpdir generate } | complete)
	assert ($without_force.stdout | str contains "false") $"expected 'false' without --force, got: ($without_force.stdout)"
	rm -rf $tmpdir
}

def test_generate_file_filtering [] {
	print "test generate filters rules by output files..."
	let tmpdir = (mktemp -d)
	'say:
  generate:
    rulemap:
      auto-gomplate: null
      auto-cue: null
      gen-a:
        cmds:
          - do: "print GEN_A; \"a\" | save a.txt"
            outputs:
              - a.txt
      gen-b:
        cmds:
          - do: "print GEN_B; \"b\" | save b.txt"
            outputs:
              - b.txt
' | save ($tmpdir | path join ".say.yaml")
	let result = (do { nu sayt.nu -d $tmpdir generate a.txt } | complete)
	assert ($result.exit_code == 0) $"generate should exit 0, got: ($result.exit_code) ($result.stderr)"
	assert ($result.stdout | str contains "GEN_A") $"expected GEN_A, got: ($result.stdout)"
	assert (not ($result.stdout | str contains "GEN_B")) $"unexpected GEN_B in output, should be filtered: ($result.stdout)"
	assert ($tmpdir | path join "a.txt" | path exists) "a.txt should be created"
	assert (not ($tmpdir | path join "b.txt" | path exists)) "b.txt should not be created"
	rm -rf $tmpdir
}

def test_generate_output_validation_fails [] {
	print "test generate fails when requested output file not created..."
	let tmpdir = (mktemp -d)
	'say:
  generate:
    rulemap:
      auto-gomplate: null
      auto-cue: null
      noop:
        cmds:
          - do: "print NOOP"
            outputs:
              - missing.txt
' | save ($tmpdir | path join ".say.yaml")
	let result = (do { nu sayt.nu -d $tmpdir generate missing.txt } | complete)
	assert ($result.exit_code != 0) $"generate should fail when output missing, got exit: ($result.exit_code)"
	rm -rf $tmpdir
}

def test_generate_script_override [] {
	print "test .sayt.generate.nu overrides generate config rules..."
	let tmpdir = (mktemp -d)
	'say:
  generate:
    rulemap:
      auto-gomplate: null
      auto-cue: null
      should-not-run:
        cmds:
          - do: "print SHOULD_NOT_RUN"
' | save ($tmpdir | path join ".say.yaml")
	'def main [...args] { print "GENERATE_SCRIPT_OVERRIDE" }
' | save ($tmpdir | path join ".sayt.generate.nu")
	let result = (do { nu sayt.nu -d $tmpdir generate } | complete)
	assert ($result.stdout | str contains "GENERATE_SCRIPT_OVERRIDE") $"expected GENERATE_SCRIPT_OVERRIDE, got: ($result.stdout)"
	assert (not ($result.stdout | str contains "SHOULD_NOT_RUN")) $"config rule should not run when script overrides, got: ($result.stdout)"
	rm -rf $tmpdir
}

def test_lint_runs_all_rules [] {
	print "test lint executes all matching rules (run-all mode)..."
	let tmpdir = (mktemp -d)
	'say:
  lint:
    rulemap:
      auto-cue: null
      lint-a:
        cmds:
          - do: "print LINT_A"
      lint-b:
        cmds:
          - do: "print LINT_B"
' | save ($tmpdir | path join ".say.yaml")
	let result = (do { nu sayt.nu -d $tmpdir lint } | complete)
	assert ($result.exit_code == 0) $"lint should exit 0, got: ($result.exit_code) ($result.stderr)"
	assert ($result.stdout | str contains "LINT_A") $"expected LINT_A, got: ($result.stdout)"
	assert ($result.stdout | str contains "LINT_B") $"expected LINT_B, got: ($result.stdout)"
	rm -rf $tmpdir
}

def test_lint_script_override [] {
	print "test .sayt.lint.nu overrides lint config rules..."
	let tmpdir = (mktemp -d)
	'def main [...args] { print "LINT_SCRIPT_OVERRIDE" }
' | save ($tmpdir | path join ".sayt.lint.nu")
	let result = (do { nu sayt.nu -d $tmpdir lint } | complete)
	assert ($result.stdout | str contains "LINT_SCRIPT_OVERRIDE") $"expected LINT_SCRIPT_OVERRIDE, got: ($result.stdout)"
	rm -rf $tmpdir
}

def test_multi_cmd_passes_args_as_env [] {
	print "test multi-cmd rule passes args via SAYT_VERB_ARGS env..."
	let tmpdir = (mktemp -d)
	'say:
  verify:
    rulemap:
      custom:
        priority: -1
        stop: true
        cmds:
          - do: "print CMD1"
          - do: "print $env.SAYT_VERB_ARGS"
' | save ($tmpdir | path join ".say.yaml")
	let result = (do { nu sayt.nu -d $tmpdir verify --my-arg value } | complete)
	assert ($result.exit_code == 0) $"verify should exit 0, got: ($result.exit_code) ($result.stderr)"
	assert ($result.stdout | str contains "CMD1") $"expected CMD1, got: ($result.stdout)"
	assert ($result.stdout | str contains "--my-arg value") $"expected args in SAYT_VERB_ARGS, got: ($result.stdout)"
	rm -rf $tmpdir
}
