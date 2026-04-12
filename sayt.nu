#!/usr/bin/env nu
use std log
use dind.nu
use tools.nu [run-cue run-docker run-docker-compose run-goreleaser run-mise run-nu vrun]
use semver.nu
use compose.nu [dind-vrun compose-vup compose-vrun]
use config.nu [load-config "path relpath"]

def --wrapped main [
	--help (-h),              # show this help message
	--directory (-d) = ".",   # directory where to run the command
	--install,                # install sayt binary for local user
	--global (-g),            # expands with --install for all users
	--commit,                 # install wrapper scripts to current directory
	--where (-w): string,     # select verb target (bare, repo, local, docker, preview, production, lts)
	...rest
] {
	cd $directory

	# Handle --install flag
	if $install {
		install-sayt --global=$global
		return
	}

	# Error if --global used without --install
	if $global and not $install {
		print -e "Error: --global requires --install"
		exit 1
	}

	# Handle --commit flag
	if $commit {
		commit-wrappers
		return
	}

	# Version pinning: read distribution version and compare with config pin
	let dist_version = open ($env.FILE_PWD | path join "VERSION") | str trim
	let config = load-config
	let target_version = $config.say?.self?.version? | default $dist_version
	if ($target_version != $dist_version) {
		re-exec-with-version $target_version $rest
	}

	let module_name = ($env.CURRENT_FILE | path basename | path parse | get stem)
	let subcommands = (scope commands | where name =~ "^main " | get name | each { |cmd| $cmd | str replace "main " "" })

	if ($rest | is-empty) {
		print (help main)
		return
	}

	let subcommand = $rest | first
	let args = $rest | skip 1

	if $help {
		run-nu $"($env.FILE_PWD)/sayt.nu" help $subcommand
		return
	}

	if not ($subcommand in $subcommands) {
		print -e $"Unknown subcommand: ($subcommand)"
		print ""
		print (help main)
		return
	}

	# Resolve where: CLI > verb config flags > self config flags > built-in default
	let verb_flags_matches = $config.say? | default {} | get -o $subcommand | default {} | get -o flags | default "" | parse --regex '--where\s+(\S+)' | get -o capture0 | default []
	let verb_flags_where = if ($verb_flags_matches | is-empty) { null } else { $verb_flags_matches | first }
	let self_flags_matches = $config.say?.self?.flags? | default "" | parse --regex '--where\s+(\S+)' | get -o capture0 | default []
	let self_flags_where = if ($self_flags_matches | is-empty) { null } else { $self_flags_matches | first }
	let builtin_default = $config.say? | default {} | get -o $subcommand | default {} | get -o where | default "local"
	let resolved_where = if ($where | is-not-empty) { $where } else if ($verb_flags_where != null) { $verb_flags_where } else if ($self_flags_where != null) { $self_flags_where } else { $builtin_default }

	with-env { SAYT_WHERE: $resolved_where } {
		run-nu $"($env.FILE_PWD)/sayt.nu" $subcommand ...$args
	}
}

# Shows help information for subcommands
export def "main help" [
	subcommand?: string  # Subcommand to show help for
] {
	if ($subcommand | is-empty) {
		help main
	} else {
		let module_name = ($env.CURRENT_FILE | path basename | path parse | get stem)
		nu -c $"use ($env.CURRENT_FILE); help ($module_name) main ($subcommand)"
	}
}

# Installs runtimes and tools for the project (configurable via say.setup)
export def --wrapped "main setup" [...args] { run-verb setup ...$args }

# Runs environment diagnostics for required tooling (configurable via say.doctor)
export def --wrapped "main doctor" [...args] { run-verb doctor ...$args }

# Generates files according to SAY config rules (configurable via say.generate)
export def "main generate" [--force (-f), ...args] {
	with-env { SAY_GENERATE_ARGS_FORCE: $force } {
		run-verb generate ...$args
	}
}

# Runs lint rules from the SAY configuration (configurable via say.lint)
export def --wrapped "main lint" [...args] { run-verb lint ...$args }

# Runs the configured build task (configurable via say.build)
export def --wrapped "main build" [...args] { run-verb build ...$args }

# Runs the configured test task (configurable via say.test)
export def --wrapped "main test" [...args] { run-verb test ...$args }

# Launches the containerized environment (configurable via say.launch)
export def --wrapped "main launch" [...args] { run-verb launch ...$args }

# Runs integration tests (configurable via say.integrate)
export def --wrapped "main integrate" [...args] { run-verb integrate ...$args }

# Prints a host.env payload suitable for dind.sh (used in CI builds)
export def "main dind-env-file" [
	--socat
	--unset-otel
] {
	dind env-file --socat=$socat --unset-otel=$unset_otel
}

# Releases artifacts (configurable via say.release)
export def --wrapped "main release" [...args] { run-verb release ...$args }

# Runs post-deploy verification (configurable via say.verify, default: nop)
export def --wrapped "main verify" [...args] { run-verb verify ...$args }

# Installs sayt binary to user or system directory
def install-sayt [
	--global (-g)  # install system-wide for all users
] {
	# Find the sayt binary - check cache symlink first, then look for arch-specific binary
	let cache_dir = get-cache-dir
	let sayt_link = $cache_dir | path join "sayt"
	let sayt_bin = if ($sayt_link | path exists) {
		$sayt_link
	} else {
		# Find the arch-specific binary in cache
		let bins = glob ($cache_dir | path join "sayt-*") | where { |f| ($f | path parse | get extension) == "" or ($f | str ends-with ".exe") }
		if ($bins | is-empty) {
			print -e "No sayt binary found in cache. Run saytw first to download it."
			exit 1
		}
		$bins | first
	}

	let is_windows = $nu.os-info.name == 'Windows'
	let target_dir = match [$global, $is_windows] {
		[true, true] => 'C:\Program Files\sayt'
		[true, false] => "/usr/local/bin"
		[false, true] => ($env.LOCALAPPDATA | path join "Programs" "sayt")
		[false, false] => ($env.HOME | path join ".local" "bin")
	}

	mkdir $target_dir
	let bin_name = if $is_windows { "sayt.exe" } else { "sayt" }
	let target = $target_dir | path join $bin_name
	cp $sayt_bin $target

	print $"sayt installed to ($target)"
	print ""

	if $global {
		if $is_windows {
			print $"Add ($target_dir) to your system PATH if not already present."
		} else {
			print "/usr/local/bin is typically already in PATH."
		}
	} else {
		print $"Ensure ($target_dir) is in your PATH."
		if not $is_windows {
			print "Add this to your shell profile:"
			print $"  export PATH=\"($target_dir):$PATH\""
		}
	}
}

def get-cache-dir [] {
	# Match saytw behavior: use XDG_CACHE_HOME or ~/.cache on Unix, LOCALAPPDATA on Windows
	if ($nu.os-info.name == 'Windows') {
		if ($env.LOCALAPPDATA? | is-not-empty) {
			$env.LOCALAPPDATA | path join "sayt"
		} else {
			"C:\\Temp\\sayt"
		}
	} else {
		if ($env.XDG_CACHE_HOME? | is-not-empty) {
			$env.XDG_CACHE_HOME | path join "sayt"
		} else {
			$env.HOME | path join ".cache" "sayt"
		}
	}
}

# Re-exec through saytw with a pinned version
def re-exec-with-version [target_version: string, rest: list<string>] {
	let saytw_name = if ($nu.os-info.name == 'Windows') { "saytw.ps1" } else { "saytw" }
	let saytw_path = $env.FILE_PWD | path join $saytw_name
	if not ($saytw_path | path exists) {
		print -e $"Error: version pin requires ($saytw_name) colocated with sayt.nu at ($env.FILE_PWD)"
		exit 1
	}

	with-env { SAYT_VERSION: $target_version } {
		^$saytw_path ...$rest
	}
}

# Downloads saytw and saytw.ps1 wrapper scripts to current directory and commits them
def commit-wrappers [] {
	let version = $env.SAYT_VERSION? | default (open ($env.FILE_PWD | path join "VERSION") | str trim)
	let base_url = $"https://raw.githubusercontent.com/bonisoft3/sayt/($version)"

	# Verify we're in a git repository
	if not (".git" | path exists) and (do { git rev-parse --git-dir } | complete | get exit_code) != 0 {
		print -e "Error: Not in a git repository. Run this from a git-tracked directory."
		exit 1
	}

	print $"Downloading wrapper scripts \(($version)\)..."

	# Download saytw (Unix)
	let saytw_url = $"($base_url)/saytw"
	http get $saytw_url | save -f saytw
	if ($nu.os-info.name != 'Windows') {
		chmod +x saytw
	}
	print "  Downloaded saytw"

	# Download saytw.ps1 (Windows)
	let saytw_ps1_url = $"($base_url)/saytw.ps1"
	http get $saytw_ps1_url | save -f saytw.ps1
	print "  Downloaded saytw.ps1"

	# Commit only these two files (--only ignores other staged changes)
	git add saytw saytw.ps1
	git commit --only saytw saytw.ps1 -m "chore: add sayt wrapper scripts

saytw: POSIX shell wrapper for macOS/Linux
saytw.ps1: PowerShell wrapper for Windows

These scripts auto-download and cache the sayt binary on first run,
enabling zero-install bootstrap for contributors."

	print ""
	print "Wrapper scripts committed successfully."
	print "Contributors can now run ./saytw (Unix) or .\\saytw.ps1 (Windows) without installing sayt globally."
}



# Check if a .sayt script implements a given verb.
# - .sayt.<verb>.nu: file existence is the signal
# - .sayt.nu: introspect exported commands for "main <verb>"
def has-sayt-verb [verb: string] {
	if ($".sayt.($verb).nu" | path exists) { return true }
	if ('.sayt.nu' | path exists) {
		let count = (run-nu -c $"use .sayt.nu; scope commands | where name == '.sayt main ($verb)' | length" | str trim | into int)
		return ($count > 0)
	}
	false
}

# Dispatch a verb through the override chain:
# 1. .sayt.<verb>.nu script (per-verb file)
# 2. .sayt.nu script (if it defines "main <verb>")
# 3. Config-driven rules from say.<verb> in .say.* files / config.cue
def --wrapped run-verb [verb: string, ...args] {
	# Handle --help: redirect to the help system
	if ("--help" in $args) or ("-h" in $args) {
		run-nu $"($env.FILE_PWD)/sayt.nu" help $verb
		return
	}

	# Layer 1: Per-verb script override
	if ($".sayt.($verb).nu" | path exists) {
		run-nu -I $env.FILE_PWD $".sayt.($verb).nu" ...$args
		return
	}

	# Layer 2: General .sayt.nu script (only if it defines this verb)
	if ('.sayt.nu' | path exists) {
		let count = (run-nu -I $env.FILE_PWD -c $"use .sayt.nu; scope commands | where name == '.sayt main ($verb)' | length" | str trim | into int)
		if ($count > 0) {
			run-nu -I $env.FILE_PWD '.sayt.nu' $verb ...$args
			return
		}
	}

	# Layer 3: Config-driven dispatch
	let config = try { load-config } catch { { say: {} } }
	let verb_config = $config.say? | default {} | get -o $verb | default {}
	let rules = $verb_config.rules? | default []

	if ($rules | is-empty) {
		return  # No rules = nop
	}

	# Filter rules by where
	let verb_default_where = $verb_config.where? | default "local"
	let resolved_where = $env.SAYT_WHERE? | default $verb_default_where
	let targeted_rules = $rules | where { |rule|
		let rule_where = $rule.where? | default null
		if ($rule_where == null) {
			# Rules without a target field match only the verb's default where
			$resolved_where == $verb_default_where
		} else {
			$rule_where == $resolved_where
		}
	}

	# If where was explicitly set and no rules match, error
	if ($targeted_rules | is-empty) and ($resolved_where != $verb_default_where) {
		print -e $"Error: no rule for target '($resolved_where)' in verb '($verb)'"
		exit 1
	}

	let rules = if ($targeted_rules | is-empty) { $rules } else { $targeted_rules }

	# Generate: filter rules by output files when file args provided
	let rules = if ($verb == "generate" and ($args | is-not-empty)) {
		let file_set = $args
		let filtered = $rules | where { |rule|
			$rule.cmds | any { |cmd|
				$cmd.outputs? | default [] | any { |output| $output in $file_set }
			}
		}
		if ($filtered | is-empty) { $rules } else { $filtered }
	} else { $rules }

	for rule in $rules {
		let cmds = $rule.cmds? | default []
		if ($cmds | is-empty) { continue }

		# Merge args: verb-level args (for default where only) + rulemap entry args + CLI passthrough
		let verb_args = if ($resolved_where == $verb_default_where) {
			$verb_config.args? | default "" | str trim
		} else { "" }
		let rule_args = $rule.args? | default "" | str trim
		let merged_parts = [
			$verb_args,
			$rule_args,
			...($args | each { |a| if ($a | str contains ' ') { $a | to nuon } else { $a } })
		] | where { |p| $p != "" }
		let args = $merged_parts | str join " " | split row " " | where { |a| $a != "" }

		if ($verb == "generate") {
			# Generate: run commands with force env, no arg passthrough
			for cmd in $cmds {
				let use_stmt = if ($cmd.use? | is-empty) { "" } else { $"use ($cmd.use);" }
				let force = $env.SAY_GENERATE_ARGS_FORCE? | default false
				run-nu -I ($env.FILE_PWD | path relpath $env.PWD) -c $"($use_stmt)with-env { SAY_GENERATE_ARGS_FORCE: ($force) } { ($cmd.do) }"
			}
		} else if ($cmds | length) == 1 {
			# Single cmd: passthrough args
			let cmd = $cmds | first
			let use_stmt = if ($cmd.use? | is-empty) { "" } else { $"use ($cmd.use);" }
			let args_str = ($args | each { |a| if ($a | str contains ' ') { $a | to nuon } else { $a } } | str join ' ')
			run-nu -I ($env.FILE_PWD | path relpath $env.PWD) -c $"($use_stmt) ($cmd.do) ($args_str)"
		} else {
			# Multi cmd: args as env var
			let args_str = ($args | str join ' ')
			for cmd in $cmds {
				let use_stmt = if ($cmd.use? | is-empty) { "" } else { $"use ($cmd.use);" }
				with-env { SAYT_VERB_ARGS: $args_str } {
					run-nu -I ($env.FILE_PWD | path relpath $env.PWD) -c $"($use_stmt) ($cmd.do)"
				}
			}
		}

		if ($rule.stop? | default false) { return }
	}

	# Generate: validate requested outputs exist
	if ($verb == "generate") {
		for file in $args {
			if (not ($file | path exists)) {
				print -e $"Failed to generate ($file)"
				exit -1
			}
		}
	}
}


