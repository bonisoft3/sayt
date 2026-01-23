#!/usr/bin/env nu
# Tests for sayt.nu --install, --commit, and --global flags
# Run with: nu sayt_flags_test.nu

use std/assert

def main [] {
	print "Running sayt flags tests...\n"

	test_help_shows_install_flag
	test_help_shows_global_flag
	test_help_shows_commit_flag
	test_commit_in_temp_git_repo

	print "\nAll flags tests passed!"
}

def test_help_shows_install_flag [] {
	print "test --install flag appears in help..."
	let result = (nu sayt.nu --help)
	assert ($result | str contains "--install")
	assert ($result | str contains "~/.local/bin")
}

def test_help_shows_global_flag [] {
	print "test --global flag appears in help..."
	let result = (nu sayt.nu --help)
	assert ($result | str contains "--global")
	assert ($result | str contains "/usr/local/bin")
}

def test_help_shows_commit_flag [] {
	print "test --commit flag appears in help..."
	let result = (nu sayt.nu --help)
	assert ($result | str contains "--commit")
	assert ($result | str contains "wrapper scripts")
}

def test_commit_in_temp_git_repo [] {
	print "test --commit downloads wrappers and commits to git repo..."

	# Create a temp directory
	let temp_dir = (mktemp -d)

	try {
		# Initialize a git repo in temp dir
		cd $temp_dir
		git init --initial-branch=main | ignore
		git config user.email "test@test.com"
		git config user.name "Test User"

		# Create an initial commit (git requires at least one commit before we can commit more)
		"initial" | save README.md
		git add README.md
		git commit -m "Initial commit" | ignore

		# Run sayt --commit
		let sayt_path = $env.FILE_PWD | path join "sayt.nu"
		nu $sayt_path --commit

		# Verify files were created
		assert ("saytw" | path exists) "saytw should exist"
		assert ("saytw.ps1" | path exists) "saytw.ps1 should exist"

		# Verify files were committed
		let log = (git log --oneline | lines | first)
		assert ($log | str contains "wrapper") "commit message should mention wrapper scripts"

		# Verify saytw is executable (Unix only)
		if ((sys host | get name) != 'Windows') {
			let mode = (ls -l saytw | get mode | first)
			assert ($mode | str contains "x") "saytw should be executable"
		}

		print "  saytw and saytw.ps1 committed successfully"
	} catch { |e|
		# Cleanup on error
		cd $env.FILE_PWD
		rm -rf $temp_dir
		error make { msg: $"test_commit_in_temp_git_repo failed: ($e.msg)" }
	}

	# Cleanup
	cd $env.FILE_PWD
	rm -rf $temp_dir
}
