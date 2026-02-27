#!/usr/bin/env nu
# Tests for sayt.nu release and verify verbs
# Run with: nu sayt_release_test.nu

use std/assert

def main [] {
	print "Running sayt release and verify tests...\n"

	test_release_help_shows_in_main
	test_verify_help_shows_in_main
	test_release_fails_without_goreleaser_config
	test_verify_fails_without_skaffold_config

	print "\nAll release and verify tests passed!"
}

def test_release_help_shows_in_main [] {
	print "test 'release' appears in main help..."
	let result = (nu sayt.nu --help)
	assert ($result | str contains "release")
	assert ($result | str contains "goreleaser")
}

def test_verify_help_shows_in_main [] {
	print "test 'verify' appears in main help..."
	let result = (nu sayt.nu --help)
	assert ($result | str contains "verify")
	assert ($result | str contains "deployed")
}

def test_release_fails_without_goreleaser_config [] {
	print "test release fails in empty temp dir..."
	let tmpdir = (mktemp -d)
	try {
		nu sayt.nu -d $tmpdir release
		rm -rf $tmpdir
		assert false "release should have failed but succeeded"
	} catch {
		rm -rf $tmpdir
		assert true
	}
}

def test_verify_fails_without_skaffold_config [] {
	print "test verify fails in empty temp dir..."
	let tmpdir = (mktemp -d)
	try {
		nu sayt.nu -d $tmpdir verify
		rm -rf $tmpdir
		assert false "verify should have failed but succeeded"
	} catch {
		rm -rf $tmpdir
		assert true
	}
}
