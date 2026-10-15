#!/usr/bin/env nu
# Tests for say.<verb>.keep_going: every rule runs past a failing one,
# the verb still fails, and the cmds within one rule stay fail-fast.
# Run with: nu keep_going_test.nu (from plugins/sayt directory)

use std/assert

def main [] {
	print "Running keep_going tests...\n"

	test_keep_going_runs_later_rules
	test_default_stops_at_first_failure
	test_keep_going_reports_nu_error
	test_keep_going_counts_rules_that_ran
	test_rules_log_their_output_below_verbose

	print "\nAll keep_going tests passed!"
}

# Two rules: `boom` fails on its first cmd (its second cmd would write
# skipped.txt), then `mark` writes marker.txt.
def make-project [keep_going: bool] {
	let tmpdir = (mktemp -d)
	let keep_line = if $keep_going { "    keep_going: true\n" } else { "" }
	$"say:
  build:
($keep_line)    rulemap:
      builtin: null
      boom:
        priority: 1
        cmds:
          - do: \"exit 3\"
          - do: \"'x' | save skipped.txt\"
      mark:
        priority: 2
        cmds:
          - do: \"'x' | save marker.txt\"
" | save ($tmpdir | path join ".say.yaml")
	$tmpdir
}

def test_keep_going_runs_later_rules [] {
	print "test keep_going runs every rule and fails at the end..."
	let tmpdir = (make-project true)
	let result = (do { nu sayt.nu -d $tmpdir build } | complete)
	assert ($result.exit_code == 1) $"expected exit 1, got ($result.exit_code): ($result.stderr)"
	assert ($tmpdir | path join "marker.txt" | path exists) "the rule after the failing one should run"
	assert (not ($tmpdir | path join "skipped.txt" | path exists)) "a failing cmd should end its own rule"
	assert ($result.stderr | str contains "sayt: rule 'boom' failed (exit 3)") $"expected the failed rule named, got: ($result.stderr)"
	assert ($result.stderr | str contains "1 of 2 rules failed: boom") $"expected the summary, got: ($result.stderr)"
	rm -rf $tmpdir
}

def test_keep_going_reports_nu_error [] {
	print "test keep_going surfaces a nushell error's message..."
	let tmpdir = (mktemp -d)
	r#'say:
  build:
    keep_going: true
    rulemap:
      builtin: null
      boom:
        priority: 1
        cmds:
          - do: 'error make {msg: "custom boom"}'
      mark:
        priority: 2
        cmds:
          - do: "'x' | save marker.txt"
'# | save ($tmpdir | path join ".say.yaml")
	let result = (do { nu sayt.nu -d $tmpdir build } | complete)
	assert ($result.exit_code == 1) $"expected exit 1, got ($result.exit_code): ($result.stderr)"
	assert ($result.stderr | str contains "sayt: rule 'boom' failed") $"expected the failed rule named, got: ($result.stderr)"
	assert ($result.stderr | str contains "custom boom") $"expected the error message, got: ($result.stderr)"
	assert ($tmpdir | path join "marker.txt" | path exists) "the rule after the failing one should run"
	rm -rf $tmpdir
}

def test_keep_going_counts_rules_that_ran [] {
	print "test keep_going's summary counts only the rules that ran..."
	let tmpdir = (mktemp -d)
	r#'say:
  build:
    keep_going: true
    rulemap:
      builtin: null
      boom:
        priority: 1
        stop: true
        cmds:
          - do: "exit 3"
      later:
        priority: 2
        cmds:
          - do: "'x' | save later.txt"
'# | save ($tmpdir | path join ".say.yaml")
	let result = (do { nu sayt.nu -d $tmpdir build } | complete)
	assert ($result.exit_code == 1) $"expected exit 1, got ($result.exit_code): ($result.stderr)"
	assert (not ($tmpdir | path join "later.txt" | path exists)) "stop should end the loop even when its rule failed"
	assert ($result.stderr | str contains "1 of 1 rules failed: boom") $"expected only the rule that ran counted, got: ($result.stderr)"
	rm -rf $tmpdir
}

def test_default_stops_at_first_failure [] {
	print "test without keep_going the first failing rule ends the verb..."
	let tmpdir = (make-project false)
	let result = (do { nu sayt.nu -d $tmpdir build } | complete)
	assert ($result.exit_code != 0) $"expected nonzero exit, got 0: ($result.stdout)"
	assert (not ($tmpdir | path join "marker.txt" | path exists)) "no rule should run after the failing one"
	assert (not ($tmpdir | path join "skipped.txt" | path exists)) "a failing cmd should end its own rule"
	rm -rf $tmpdir
}

# A rule's cmds run through run-live like any other command: below verbose a
# passing rule's output goes to a log, and a failure prints it and keeps its code.
def test_rules_log_their_output_below_verbose [] {
	print "test rule output follows the output level..."
	for keep_going in [true false] {
		let tmpdir = (mktemp -d)
		let keep_line = if $keep_going { "    keep_going: true\n" } else { "" }
		$"say:
  build:
($keep_line)    rulemap:
      builtin: null
      chatty:
        priority: 1
        cmds:
          - do: \"print chatter\"
      boom:
        priority: 2
        cmds:
          - do: \"print why; exit 3\"
" | save ($tmpdir | path join ".say.yaml")
		let expected = if $keep_going { 1 } else { 3 }
		for level in [normal quiet] {
			let r = (with-env {SAYT_VERBOSITY: $level} { do { nu sayt.nu -d $tmpdir build } | complete })
			assert equal $r.exit_code $expected $"($level) keep_going=($keep_going): ($r.stderr)"
			assert not ($r.stdout + $r.stderr | lines | any { |l| $l == "chatter" }) $"($level) printed a passing rule: ($r.stderr)"
			assert ($r.stdout | lines | any { |l| $l == "why" }) $"($level) lost the failure's log: ($r.stdout)"
			assert ($r.stderr | str contains "✗ build boom exit 3") $"($level) verdict does not name the rule: ($r.stderr)"
			if $keep_going {
				assert ($r.stderr | str contains "sayt: rule 'boom' failed (exit 3)") $"expected the failed rule named, got: ($r.stderr)"
			}
		}
		let v = (with-env {SAYT_VERBOSITY: verbose} { do { nu sayt.nu -d $tmpdir build } | complete })
		assert ($v.stdout | str contains "chatter") $"verbose did not stream a rule: ($v)"
		rm -rf $tmpdir
	}
}
