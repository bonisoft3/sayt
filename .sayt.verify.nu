#!/usr/bin/env nu
# Verify: fetch the published install script for the current version,
# run it into a temp directory, and smoke-test the installed binary.
# Also verify that version pinning correctly downgrades to an older release.

def main [...args] {
	let version = open ($env.FILE_PWD | path join "VERSION") | str trim
	print $"Verifying install of ($version)"

	let tmpdir = (mktemp -d)
	let url = $"https://raw.githubusercontent.com/bonisoft3/sayt/($version)/saytw"

	print $"Fetching ($url)"
	http get $url | save ($tmpdir | path join "saytw")
	chmod +x ($tmpdir | path join "saytw")

	# Run from tmpdir so mise doesn't pick up the plugin dir's .mise.toml
	# (which would be untrusted under the fake HOME).
	let install_result = with-env { HOME: $tmpdir, SAYT_VERSION: $version } {
		do { cd $tmpdir; ^./saytw --install } | complete
	}
	if $install_result.exit_code != 0 {
		print -e $"FAIL: install exited with ($install_result.exit_code)"
		print -e $"  stderr: ($install_result.stderr | str substring 0..500)"
		rm -rf $tmpdir
		exit 1
	}
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

	# Version pin downgrade test
	verify-version-pin $version
}

# Verify that a .say.yaml version pin triggers a downgrade to v0.2.0.
# Creates a temp project pinned to v0.2.0, runs the latest sayt against it,
# and checks that the re-exec mechanism downloaded the v0.2.0 binary.
def verify-version-pin [version: string] {
	let pin = "v0.2.0"
	let dist_version = open ($env.FILE_PWD | path join "VERSION") | str trim

	if $dist_version == $pin {
		print $"\nSKIP: dist version already matches pin ($pin)"
		return
	}

	print $"\nVerifying version pin downgrade \(($dist_version) → ($pin)\)"

	let tmpdir = (mktemp -d)
	let cache_dir = (mktemp -d)

	# Create a project whose .say.yaml pins sayt to v0.2.0
	$'say:
  self:
    version: "($pin)"
' | save ($tmpdir | path join ".say.yaml")

	# Run the latest sayt (development sayt.nu with version pinning).
	# It detects the mismatch and re-execs via colocated saytw with
	# SAYT_VERSION=v0.2.0. saytw downloads the published v0.2.0 binary
	# into XDG_CACHE_HOME/sayt/v0.2.0/.
	let sayt_nu = $env.FILE_PWD | path join "sayt.nu"
	print $"  running: sayt -d ($tmpdir | path basename) help"
	let result = with-env { XDG_CACHE_HOME: $cache_dir } {
		do { ^nu $sayt_nu -d $tmpdir help } | complete
	}

	# saytw prints "Downloading sayt v0.2.0 ..." to stderr
	let pin_cache = $cache_dir | path join "sayt" $pin
	let has_cached = $pin_cache | path exists
	let has_stderr = $result.stderr | str contains $pin

	if not $has_cached and not $has_stderr {
		print -e $"FAIL: no evidence of downgrade to ($pin)"
		print -e $"  cache exists: ($has_cached) \(($pin_cache)\)"
		print -e $"  stderr mentions pin: ($has_stderr)"
		if ($result.stderr | is-not-empty) {
			print -e $"  stderr: ($result.stderr | str substring 0..500)"
		}
		rm -rf $tmpdir $cache_dir
		exit 1
	}

	if $has_cached { print $"  OK: ($pin) binary cached" }
	if $has_stderr { print $"  OK: stderr confirms ($pin) download" }

	rm -rf $tmpdir $cache_dir
	print $"Version pin downgrade to ($pin) verified"
}
