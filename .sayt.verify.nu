#!/usr/bin/env nu
# Verify: fetch the published install script for the latest release tag,
# run it into a temp directory, and smoke-test the installed binary.
use semver.nu [resolve-version-tags]

def main [...args] {
	let version = (resolve-version-tags).current
	print $"Verifying install of ($version)"

	let tmpdir = (mktemp -d)
	let url = $"https://raw.githubusercontent.com/bonisoft3/sayt/($version)/saytw"

	print $"Fetching ($url)"
	http get $url | with-env { HOME: $tmpdir, SAYT_VERSION: $version } { ^sh -s -- --install }
	print "  OK: install succeeded"

	let binary = $tmpdir | path join ".local" "bin" "sayt"
	if not ($binary | path exists) {
		print -e $"FAIL: binary not found at ($binary)"
		rm -rf $tmpdir
		exit 1
	}
	print $"  OK: binary at ($binary)"

	# Smoke test: --help shows expected verbs
	print "  test: sayt --help"
	let help_result = (do { ^$binary --help } | complete)
	if $help_result.exit_code != 0 {
		print -e $"FAIL: --help exited with ($help_result.exit_code)"
		rm -rf $tmpdir
		exit 1
	}
	for keyword in ["setup" "build" "test" "integrate" "verify"] {
		if not ($help_result.stdout | str contains $keyword) {
			print -e $"FAIL: --help output missing '($keyword)'"
			rm -rf $tmpdir
			exit 1
		}
	}
	print "  OK: help contains all verbs"

	rm -rf $tmpdir
	print $"\nVerification passed for ($version)"
}
