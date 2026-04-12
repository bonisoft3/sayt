#!/usr/bin/env nu
# Tests for sayt.nu --install, --commit, and --global flags
# Run with: nu sayt_flags_test.nu

use std/assert

def main [] {
	print "Running sayt flags tests...\n"

	test_help_shows_install_flag
	test_help_shows_global_flag
	test_help_shows_commit_flag
	test_help_shows_where_flag
	test_help_does_not_show_task_flag

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

def test_help_shows_where_flag [] {
	print "test --where flag appears in help..."
	let result = (nu sayt.nu --help)
	assert ($result | str contains "--where")
}

def test_help_does_not_show_task_flag [] {
	print "test --task flag is gone from help..."
	let result = (nu sayt.nu --help)
	assert (not ($result | str contains "--task")) "expected --task removed from help"
}

