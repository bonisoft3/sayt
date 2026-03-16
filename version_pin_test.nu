#!/usr/bin/env nu
# Tests for version pinning: VERSION file reading, re-exec behavior
# Run with: nu version_pin_test.nu (from plugins/sayt directory)

use std/assert

def main [] {
	print "Running version pin tests...\n"

	test_no_pin_no_reexec
	test_pin_matches_dist_no_reexec
	test_pin_differs_reexec
	test_saytw_not_found_aborts

	print "\nAll version pin tests passed!"
}

def make-test-dir [] {
	let tmpdir = (mktemp -d)
	$tmpdir
}

# No pin configured → no re-exec, verb runs normally
def test_no_pin_no_reexec [] {
	print "test no pin configured → no re-exec, verb runs normally..."
	let tmpdir = (make-test-dir)
	# Add a simple verify rule so we get observable output
	'say:
  verify:
    rulemap:
      custom:
        priority: -1
        cmds:
          - do: "echo NO_PIN_OK"
' | save ($tmpdir | path join ".say.yaml")
	let result = (do { nu sayt.nu -d $tmpdir verify } | complete)
	assert ($result.exit_code == 0) $"should exit 0, got ($result.exit_code): ($result.stderr)"
	assert ($result.stdout | str contains "NO_PIN_OK") $"expected NO_PIN_OK, got: ($result.stdout)"
	rm -rf $tmpdir
}

# Pin matches distribution version → no re-exec
def test_pin_matches_dist_no_reexec [] {
	print "test pin matches dist version → no re-exec..."
	let tmpdir = (make-test-dir)
	let dist_version = open VERSION | str trim
	# Pin to the same version as distribution
	$'say:
  self:
    version: "($dist_version)"
  verify:
    rulemap:
      custom:
        priority: -1
        cmds:
          - do: "echo MATCH_OK"
' | save ($tmpdir | path join ".say.yaml")
	let result = (do { nu sayt.nu -d $tmpdir verify } | complete)
	assert ($result.exit_code == 0) $"should exit 0, got ($result.exit_code): ($result.stderr)"
	assert ($result.stdout | str contains "MATCH_OK") $"expected MATCH_OK, got: ($result.stdout)"
	rm -rf $tmpdir
}

# Pin differs → re-exec with SAYT_VERSION set (fake saytw echoes env)
def test_pin_differs_reexec [] {
	print "test pin differs → re-exec with SAYT_VERSION set..."
	let tmpdir = (make-test-dir)
	# Pin to a different version
	'say:
  self:
    version: "v99.99.99"
' | save ($tmpdir | path join ".say.yaml")

	# Create a fake saytw that just echoes the SAYT_VERSION env var
	'#!/bin/sh
echo "REEXEC_VERSION=$SAYT_VERSION"
' | save ($tmpdir | path join "saytw")
	chmod +x ($tmpdir | path join "saytw")

	# We need saytw colocated with sayt.nu (in FILE_PWD), not in the target dir.
	# Copy the fake saytw to the sayt plugin directory temporarily.
	let sayt_dir = $env.FILE_PWD? | default (pwd)
	let backup_saytw = $tmpdir | path join "saytw.backup"
	let saytw_path = $sayt_dir | path join "saytw"
	# Back up the real saytw
	cp $saytw_path $backup_saytw
	# Replace with our fake
	cp ($tmpdir | path join "saytw") $saytw_path

	let result = try {
		do { nu sayt.nu -d $tmpdir verify } | complete
	} catch { |e|
		# Restore real saytw before propagating
		cp $backup_saytw $saytw_path
		error make { msg: $"test failed: ($e)" }
	}

	# Restore real saytw
	cp $backup_saytw $saytw_path

	assert ($result.stdout | str contains "REEXEC_VERSION=v99.99.99") $"expected SAYT_VERSION=v99.99.99, got: ($result.stdout)($result.stderr)"
	rm -rf $tmpdir
}

# saytw not found → aborts with error
def test_saytw_not_found_aborts [] {
	print "test saytw not found → aborts with error..."
	let tmpdir = (make-test-dir)
	# Pin to a different version but don't provide saytw
	'say:
  self:
    version: "v99.99.99"
' | save ($tmpdir | path join ".say.yaml")

	# Temporarily rename the real saytw so it's not found
	let sayt_dir = $env.FILE_PWD? | default (pwd)
	let saytw_path = $sayt_dir | path join "saytw"
	let saytw_backup = $sayt_dir | path join "saytw.pin_test_backup"
	mv $saytw_path $saytw_backup

	let result = try {
		do { nu sayt.nu -d $tmpdir verify } | complete
	} catch { |e|
		mv $saytw_backup $saytw_path
		{ exit_code: 1, stderr: $"($e)" }
	}

	# Restore
	if ($saytw_backup | path exists) {
		mv $saytw_backup $saytw_path
	}

	assert ($result.exit_code != 0) $"should fail when saytw not found, got exit ($result.exit_code)"
	assert ($result.stderr | str contains "version pin requires saytw") $"expected error about saytw, got: ($result.stderr)"
	rm -rf $tmpdir
}
