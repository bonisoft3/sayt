#!/usr/bin/env nu
# Tests for sayt.nu --install, --commit, and --global flags
# Run with: nu sayt_flags_test.nu

use std/assert

def main [] {
	print "Running sayt flags tests...\n"

	test_help_shows_install_flag
	test_help_shows_global_flag
	test_help_shows_commit_flag
	test_help_shows_platform_flag
	test_help_shows_verb_flag
	test_help_does_not_show_task_flag
	test_output_flags_reach_nested_processes

	print "\nAll flags tests passed!"
}

def test_help_shows_install_flag [] {
	print "test --install flag appears in help..."
	let result = (nu sayt.nu --help)
	assert ($result | str contains "--install")
	assert ($result | str contains "local user")
}

def test_help_shows_global_flag [] {
	print "test --global flag appears in help..."
	let result = (nu sayt.nu --help)
	assert ($result | str contains "--global")
	assert ($result | str contains "all users")
}

def test_help_shows_commit_flag [] {
	print "test --commit flag appears in help..."
	let result = (nu sayt.nu --help)
	assert ($result | str contains "--commit")
	assert ($result | str contains "wrapper")
}

def test_help_shows_platform_flag [] {
	print "test --platform flag appears in help..."
	let result = (nu sayt.nu --help)
	assert ($result | str contains "--platform")
}

def test_help_shows_verb_flag [] {
	print "test --verb flag appears in help..."
	let result = (nu sayt.nu --help)
	assert ($result | str contains "--verb")
}

def test_help_does_not_show_task_flag [] {
	print "test --task flag is gone from help..."
	let result = (nu sayt.nu --help)
	assert (not ($result | str contains "--task")) "expected --task removed from help"
}

# integrate runs as nested processes (sayt, bayt-task, task-leaf, nu); the mode
# must be decided at the top, where stdout is still the caller's terminal.
def test_output_flags_reach_nested_processes [] {
	print "test -v/-q reach a nested script..."
	let dir = (mktemp -d -t sayt-flags.XXXXXX)
	'print $"($env.SAYT_VERBOSITY)|($env.SAYT_LOG_DIR? | default none)"' | save -f $"($dir)/probe.nu"
	let quiet = (nu sayt.nu -d $dir -q --script ./probe.nu | str trim | split row "|")
	assert equal $quiet.0 "quiet"
	assert ($quiet.1 | path exists) "quiet run has no log directory"
	let piped = (with-env {SAYT_VERBOSITY: ""} { hide-env -i CI; nu sayt.nu -d $dir --script ./probe.nu | str trim | split row "|" })
	assert equal $piped.0 "normal" "a piped run did not default to normal"
	let verbose = (nu sayt.nu -d $dir -v --script ./probe.nu | str trim | split row "|")
	assert equal $verbose.0 "verbose"
	let both = (do { nu sayt.nu -d $dir -v -q --script ./probe.nu } | complete)
	assert ($both.exit_code != 0) "-v -q together were accepted"
}
