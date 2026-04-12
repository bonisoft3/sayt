#!/usr/bin/env nu
# Tests for --where flag: parsing, env var passthrough, default resolution
# Run with: nu target_test.nu (from plugins/sayt directory)

use std/assert

def main [] {
	print "Running --where flag tests...\n"

	test_target_flag_sets_env_var
	test_target_flag_short_form
	test_no_target_uses_default
	test_config_target_field_accepted
	test_verb_level_target_flags_args_accepted
	test_target_filters_rulemap
	test_target_no_match_errors
	test_rules_without_target_run_for_default
	test_verb_flags_override_default_target
	test_self_flags_apply_globally
	test_verb_args_merged_into_passthrough
	test_rulemap_args_merged
	test_simple_do_only_matches_default_target
	test_script_override_receives_target
	test_verb_args_dont_apply_to_non_default_target
	test_custom_target_name
	test_all_verb_defaults

	print "\nAll --where flag tests passed!"
}

def make-test-dir [] {
	let tmpdir = (mktemp -d)
	$tmpdir
}

def test_target_flag_sets_env_var [] {
	print "test --where sets SAYT_WHERE env var..."
	let tmpdir = (make-test-dir)
	'def --wrapped main [...args] { print $"TARGET=($env.SAYT_WHERE? | default none)" }
' | save ($tmpdir | path join ".sayt.verify.nu")
	let result = (do { nu sayt.nu --where local -d $tmpdir verify } | complete)
	assert ($result.exit_code == 0) $"expected exit 0, got ($result.exit_code): ($result.stderr)"
	assert ($result.stdout | str contains "TARGET=local") $"expected TARGET=local, got: ($result.stdout)"
	rm -rf $tmpdir
}

def test_target_flag_short_form [] {
	print "test -w short form works..."
	let tmpdir = (make-test-dir)
	'def --wrapped main [...args] { print $"TARGET=($env.SAYT_WHERE? | default none)" }
' | save ($tmpdir | path join ".sayt.verify.nu")
	let result = (do { nu sayt.nu -w local -d $tmpdir verify } | complete)
	assert ($result.exit_code == 0) $"expected exit 0, got ($result.exit_code): ($result.stderr)"
	assert ($result.stdout | str contains "TARGET=local") $"expected TARGET=local, got: ($result.stdout)"
	rm -rf $tmpdir
}

def test_no_target_uses_default [] {
	print "test no --where uses verb's built-in default..."
	let tmpdir = (make-test-dir)
	'def --wrapped main [...args] { print $"TARGET=($env.SAYT_WHERE? | default none)" }
' | save ($tmpdir | path join ".sayt.verify.nu")
	let result = (do { nu sayt.nu -d $tmpdir verify } | complete)
	assert ($result.exit_code == 0) $"expected exit 0, got ($result.exit_code): ($result.stderr)"
	assert ($result.stdout | str contains "TARGET=preview") $"expected TARGET=preview, got: ($result.stdout)"
	rm -rf $tmpdir
}

def test_config_target_field_accepted [] {
	print "test target field is accepted in .say.yaml rulemap..."
	let tmpdir = (make-test-dir)
	'say:
  verify:
    rulemap:
      custom:
        where: preview
        priority: -1
        stop: true
        cmds:
          - do: "print TARGETED_VERIFY"
' | save ($tmpdir | path join ".say.yaml")
	let result = (do { nu sayt.nu -d $tmpdir verify } | complete)
	assert ($result.exit_code == 0) $"expected exit 0, got ($result.exit_code): ($result.stderr)"
	assert ($result.stdout | str contains "TARGETED_VERIFY") $"expected TARGETED_VERIFY, got: ($result.stdout)"
	rm -rf $tmpdir
}

def test_verb_level_target_flags_args_accepted [] {
	print "test verb-level target, flags, args fields accepted in .say.yaml..."
	let tmpdir = (make-test-dir)
	'say:
  self:
    flags: "--verbose"
  verify:
    where: docker
    flags: "--where local"
    args: "--extra-arg"
    rulemap:
      custom:
        where: local
        priority: -1
        stop: true
        cmds:
          - do: "print VERB_FIELDS_OK"
' | save ($tmpdir | path join ".say.yaml")
	let result = (do { nu sayt.nu -d $tmpdir verify } | complete)
	assert ($result.exit_code == 0) $"expected exit 0, got ($result.exit_code): ($result.stderr)"
	assert ($result.stdout | str contains "VERB_FIELDS_OK") $"expected VERB_FIELDS_OK, got: ($result.stdout)"
	rm -rf $tmpdir
}

def test_target_filters_rulemap [] {
	print "test --where filters rulemap to matching entries..."
	let tmpdir = (make-test-dir)
	'say:
  launch:
    rulemap:
      compose:
        where: docker
        priority: -1
        stop: true
        cmds:
          - do: "print COMPOSE_LAUNCH"
      dapr:
        where: local
        priority: -1
        stop: true
        cmds:
          - do: "print DAPR_LAUNCH"
' | save ($tmpdir | path join ".say.yaml")
	# Default target for launch is docker -> should run compose
	let result = (do { nu sayt.nu -d $tmpdir launch } | complete)
	assert ($result.stdout | str contains "COMPOSE_LAUNCH") $"expected COMPOSE_LAUNCH for default docker target, got: ($result.stdout)"
	assert (not ($result.stdout | str contains "DAPR_LAUNCH")) $"unexpected DAPR_LAUNCH, got: ($result.stdout)"
	# Explicit --where local -> should run dapr
	let result2 = (do { nu sayt.nu --where local -d $tmpdir launch } | complete)
	assert ($result2.stdout | str contains "DAPR_LAUNCH") $"expected DAPR_LAUNCH for --where local, got: ($result2.stdout)"
	assert (not ($result2.stdout | str contains "COMPOSE_LAUNCH")) $"unexpected COMPOSE_LAUNCH, got: ($result2.stdout)"
	rm -rf $tmpdir
}

def test_target_no_match_errors [] {
	print "test --where with no matching rules errors..."
	let tmpdir = (make-test-dir)
	'say:
  launch:
    rulemap:
      compose:
        where: docker
        priority: -1
        stop: true
        cmds:
          - do: "print COMPOSE_LAUNCH"
' | save ($tmpdir | path join ".say.yaml")
	let result = (do { nu sayt.nu --where browser -d $tmpdir launch } | complete)
	assert ($result.exit_code != 0) $"expected non-zero exit for unmatched target, got: ($result.exit_code)"
	assert ($result.stderr | str contains "no rule for target") $"expected error message, got: ($result.stderr)"
	rm -rf $tmpdir
}

def test_rules_without_target_run_for_default [] {
	print "test rules without target field run for verb's default target..."
	let tmpdir = (make-test-dir)
	'say:
  verify:
    rulemap:
      custom:
        priority: -1
        stop: true
        cmds:
          - do: "print NO_TARGET_FIELD"
' | save ($tmpdir | path join ".say.yaml")
	# verify default is preview, rule has no target -> should match
	let result = (do { nu sayt.nu -d $tmpdir verify } | complete)
	assert ($result.stdout | str contains "NO_TARGET_FIELD") $"expected NO_TARGET_FIELD, got: ($result.stdout)"
	# Explicit non-default target -> should NOT match
	let result2 = (do { nu sayt.nu --where production -d $tmpdir verify } | complete)
	assert (not ($result2.stdout | str contains "NO_TARGET_FIELD")) $"unexpected NO_TARGET_FIELD for non-default target, got: ($result2.stdout)"
	rm -rf $tmpdir
}

def test_verb_flags_override_default_target [] {
	print "test verb-level flags override default target..."
	let tmpdir = (make-test-dir)
	'say:
  launch:
    flags: "--where local"
    rulemap:
      compose:
        where: docker
        priority: -1
        stop: true
        cmds:
          - do: "print COMPOSE"
      dapr:
        where: local
        priority: -1
        stop: true
        cmds:
          - do: "print DAPR"
' | save ($tmpdir | path join ".say.yaml")
	# No --where on CLI, but verb flags says --where local
	let result = (do { nu sayt.nu -d $tmpdir launch } | complete)
	assert ($result.stdout | str contains "DAPR") $"expected DAPR via verb flags, got: ($result.stdout)"
	# CLI --where should override verb flags
	let result2 = (do { nu sayt.nu --where docker -d $tmpdir launch } | complete)
	assert ($result2.stdout | str contains "COMPOSE") $"expected COMPOSE via CLI override, got: ($result2.stdout)"
	rm -rf $tmpdir
}

def test_self_flags_apply_globally [] {
	print "test self.flags apply to all verbs..."
	let tmpdir = (make-test-dir)
	'say:
  self:
    flags: "--where local"
  launch:
    rulemap:
      compose:
        where: docker
        priority: -1
        stop: true
        cmds:
          - do: "print COMPOSE"
      dapr:
        where: local
        priority: -1
        stop: true
        cmds:
          - do: "print DAPR"
' | save ($tmpdir | path join ".say.yaml")
	let result = (do { nu sayt.nu -d $tmpdir launch } | complete)
	assert ($result.stdout | str contains "DAPR") $"expected DAPR via self.flags, got: ($result.stdout)"
	rm -rf $tmpdir
}

def test_verb_args_merged_into_passthrough [] {
	print "test verb-level args merge into passthrough for default target..."
	let tmpdir = (make-test-dir)
	'say:
  verify:
    args: "--default-arg"
    rulemap:
      custom:
        priority: -1
        stop: true
        cmds:
          - do: "print VERIFY"
' | save ($tmpdir | path join ".say.yaml")
	let result = (do { nu sayt.nu -d $tmpdir verify --extra } | complete)
	assert ($result.stdout | str contains "VERIFY") $"expected VERIFY, got: ($result.stdout)"
	assert ($result.stdout | str contains "--default-arg") $"expected --default-arg from verb args, got: ($result.stdout)"
	assert ($result.stdout | str contains "--extra") $"expected --extra from CLI, got: ($result.stdout)"
	rm -rf $tmpdir
}

def test_rulemap_args_merged [] {
	print "test rulemap entry args merge into passthrough..."
	let tmpdir = (make-test-dir)
	'say:
  launch:
    rulemap:
      compose:
        where: docker
        args: "--watch"
        priority: -1
        stop: true
        cmds:
          - do: "print LAUNCH"
' | save ($tmpdir | path join ".say.yaml")
	let result = (do { nu sayt.nu -d $tmpdir launch --extra } | complete)
	assert ($result.stdout | str contains "LAUNCH") $"expected LAUNCH, got: ($result.stdout)"
	assert ($result.stdout | str contains "--watch") $"expected --watch from rulemap args, got: ($result.stdout)"
	assert ($result.stdout | str contains "--extra") $"expected --extra from CLI, got: ($result.stdout)"
	rm -rf $tmpdir
}

def test_simple_do_only_matches_default_target [] {
	print "test simple do: form only runs for default target..."
	let tmpdir = (make-test-dir)
	'say:
  verify:
    do: "print SIMPLE_VERIFY"
' | save ($tmpdir | path join ".say.yaml")
	# Default target for verify is preview -> should work
	let result = (do { nu sayt.nu -d $tmpdir verify } | complete)
	assert ($result.exit_code == 0) $"expected exit 0, got ($result.exit_code): ($result.stderr)"
	assert ($result.stdout | str contains "SIMPLE_VERIFY") $"expected SIMPLE_VERIFY, got: ($result.stdout)"
	# Explicit non-default target -> should not match simple do
	let result2 = (do { nu sayt.nu --where production -d $tmpdir verify } | complete)
	assert (not ($result2.stdout | str contains "SIMPLE_VERIFY")) $"unexpected SIMPLE_VERIFY for non-default target"
	rm -rf $tmpdir
}

def test_script_override_receives_target [] {
	print "test script override receives SAYT_WHERE env var..."
	let tmpdir = (make-test-dir)
	'def --wrapped main [...args] { print $"SCRIPT_TARGET=($env.SAYT_WHERE? | default none)" }
' | save ($tmpdir | path join ".sayt.launch.nu")
	let result = (do { nu sayt.nu --where local -d $tmpdir launch } | complete)
	assert ($result.exit_code == 0) $"expected exit 0, got ($result.exit_code): ($result.stderr)"
	assert ($result.stdout | str contains "SCRIPT_TARGET=local") $"expected SCRIPT_TARGET=local, got: ($result.stdout)"
	rm -rf $tmpdir
}

def test_verb_args_dont_apply_to_non_default_target [] {
	print "test verb-level args don't apply to non-default target..."
	let tmpdir = (make-test-dir)
	'say:
  launch:
    args: "--default-only"
    rulemap:
      compose:
        where: docker
        priority: -1
        stop: true
        cmds:
          - do: "print COMPOSE"
      local-launch:
        where: local
        priority: -1
        stop: true
        cmds:
          - do: "print LOCAL"
' | save ($tmpdir | path join ".say.yaml")
	# Default target (docker) should get verb args
	let result = (do { nu sayt.nu -d $tmpdir launch } | complete)
	assert ($result.stdout | str contains "--default-only") $"expected --default-only for default target, got: ($result.stdout)"
	# Non-default target should NOT get verb args
	let result2 = (do { nu sayt.nu --where local -d $tmpdir launch } | complete)
	assert (not ($result2.stdout | str contains "--default-only")) $"unexpected --default-only for non-default target, got: ($result2.stdout)"
	rm -rf $tmpdir
}

def test_custom_target_name [] {
	print "test custom target names (e.g. browser) work..."
	let tmpdir = (make-test-dir)
	'say:
  launch:
    rulemap:
      browser:
        where: browser
        priority: -1
        stop: true
        cmds:
          - do: "print BROWSER_LAUNCH"
' | save ($tmpdir | path join ".say.yaml")
	let result = (do { nu sayt.nu --where browser -d $tmpdir launch } | complete)
	assert ($result.exit_code == 0) $"expected exit 0, got ($result.exit_code): ($result.stderr)"
	assert ($result.stdout | str contains "BROWSER_LAUNCH") $"expected BROWSER_LAUNCH, got: ($result.stdout)"
	rm -rf $tmpdir
}

def test_all_verb_defaults [] {
	print "test built-in default targets for all verbs..."
	let tmpdir = (make-test-dir)
	'def --wrapped main [...args] { print $"TARGET=($env.SAYT_WHERE? | default none)" }
' | save ($tmpdir | path join ".sayt.setup.nu")
	let result_setup = (do { nu sayt.nu -d $tmpdir setup } | complete)
	assert ($result_setup.stdout | str contains "TARGET=bare") $"setup should default to bare, got: ($result_setup.stdout)"

	# Reuse for other verbs
	cp ($tmpdir | path join ".sayt.setup.nu") ($tmpdir | path join ".sayt.build.nu")
	let result_build = (do { nu sayt.nu -d $tmpdir build } | complete)
	assert ($result_build.stdout | str contains "TARGET=local") $"build should default to local, got: ($result_build.stdout)"

	cp ($tmpdir | path join ".sayt.setup.nu") ($tmpdir | path join ".sayt.launch.nu")
	let result_launch = (do { nu sayt.nu -d $tmpdir launch } | complete)
	assert ($result_launch.stdout | str contains "TARGET=docker") $"launch should default to docker, got: ($result_launch.stdout)"

	cp ($tmpdir | path join ".sayt.setup.nu") ($tmpdir | path join ".sayt.release.nu")
	let result_release = (do { nu sayt.nu -d $tmpdir release } | complete)
	assert ($result_release.stdout | str contains "TARGET=preview") $"release should default to preview, got: ($result_release.stdout)"

	rm -rf $tmpdir
}
