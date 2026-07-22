#!/usr/bin/env nu
use dind.nu
use rulemap.nu
use tools.nu [run-nu]
use config.nu [load-config "path relpath"]

def --wrapped main [
	--help (-h),              # show this help message
	--directory (-d) = ".",   # directory where to run the command
	--install,                # install sayt binary for local user
	--global (-g),            # expands with --install for all users
	--commit,                 # install wrapper scripts to current directory
	--platform (-w): string,  # select verb platform (bare, repo, local, docker, preview, production, lts)
	--verb: string,           # explicit verb selection (positional argument is sugar for this)
	--script: string,         # run an engine module directly (sayt's own or a project path), bypassing verb dispatch
	...rest
] {
	cd $directory

	# Engine entry: no config load, no verb dispatch — verb-level
	# config (args, rules) never applies.
	if ($script | is-not-empty) {
		run-script $script ...$rest
		return
	}

	if $install {
		install-sayt --global=$global
		return
	}

	if $global and not $install {
		print -e "Error: --global requires --install"
		exit 1
	}

	if $commit {
		commit-wrappers
		return
	}

	let config = load-config
	let module_name = ($env.CURRENT_FILE | path basename | path parse | get stem)
	let builtin_verbs = (scope commands | where name =~ "^main " | get name | each { |cmd| $cmd | str replace "main " "" })
	let custom_verbs = $config.say?.self?.verbs? | default []
	let subcommands = $builtin_verbs | append $custom_verbs | uniq

	# Resolve verb: --verb flag > first positional arg
	let subcommand_raw = if ($verb | is-not-empty) { $verb } else if ($rest | is-not-empty) { $rest | first } else { null }
	let args = if ($verb | is-not-empty) { $rest } else { $rest | skip 1 }

	if ($subcommand_raw == null) {
		print (help main)
		return
	}

	let at_parts = $subcommand_raw | split row "@"
	let subcommand = $at_parts | first
	let at_platform = if ($at_parts | length) > 1 { $at_parts | last } else { null }

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

	# Resolve platform: CLI/@syntax > verb config flags > self config flags > built-in default
	let cli_platform = if ($platform | is-not-empty) { $platform } else { $at_platform }
	let verb_flags_matches = $config.say? | default {} | get -o $subcommand | default {} | get -o flags | default "" | parse --regex '--platform\s+(\S+)' | get -o capture0 | default []
	let verb_flags_platform = if ($verb_flags_matches | is-empty) { null } else { $verb_flags_matches | first }
	let self_flags_matches = $config.say?.self?.flags? | default "" | parse --regex '--platform\s+(\S+)' | get -o capture0 | default []
	let self_flags_platform = if ($self_flags_matches | is-empty) { null } else { $self_flags_matches | first }
	let builtin_default = $config.say? | default {} | get -o $subcommand | default {} | get -o platform | default "local"
	let resolved_platform = if ($cli_platform != null) { $cli_platform } else if ($verb_flags_platform != null) { $verb_flags_platform } else if ($self_flags_platform != null) { $self_flags_platform } else { $builtin_default }

	with-env { SAYT_PLATFORM: $resolved_platform } {
		if ($subcommand in $builtin_verbs) {
			run-nu $"($env.FILE_PWD)/sayt.nu" $subcommand ...$args
		} else {
			run-verb $subcommand ...$args
		}
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
] {
	dind env-file --socat=$socat
}

# Releases artifacts (configurable via say.release)
export def --wrapped "main release" [...args] { run-verb release ...$args }

# Runs post-deploy verification (configurable via say.verify, default: nop)
export def --wrapped "main verify" [...args] { run-verb verify ...$args }

# Installs sayt binary to user or system directory
def install-sayt [
	--global (-g)  # install system-wide for all users
] {
	let cache_dir = get-cache-dir
	let sayt_link = $cache_dir | path join "sayt"
	let sayt_bin = if ($sayt_link | path exists) {
		$sayt_link
	} else {
		let bins = glob ($cache_dir | path join "sayt-*") | where { |f| ($f | path parse | get extension) == "" or ($f | str ends-with ".exe") }
		if ($bins | is-empty) {
			print -e "No sayt binary found in cache. Run saytw first to download it."
			exit 1
		}
		$bins | first
	}

	let is_windows = $nu.os-info.name == 'windows'
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
	if ($nu.os-info.name == 'windows') {
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
	let saytw_name = if ($nu.os-info.name == 'windows') { "saytw.ps1" } else { "saytw" }
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

	if not (".git" | path exists) and (do { git rev-parse --git-dir } | complete | get exit_code) != 0 {
		print -e "Error: Not in a git repository. Run this from a git-tracked directory."
		exit 1
	}

	print $"Downloading wrapper scripts \(($version)\)..."

	let saytw_url = $"($base_url)/saytw"
	http get $saytw_url | save -f saytw
	if ($nu.os-info.name != 'windows') {
		chmod +x saytw
	}
	print "  Downloaded saytw"

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



# Run an engine module with sayt's include path, without verb dispatch.
# Bare names (integrate.nu, launch.nu, ...) resolve against sayt's own
# directory; path-ish names (containing a separator or starting with a
# dot) resolve against the project cwd, covering `.sayt.<verb>.nu`-style
# scripts. A leading `--` in args is the conventional separator between
# the flag and the module's own flags — strip it.
def --wrapped run-script [script: string, ...args] {
	let args = if (($args | length) > 0) and (($args | first) == "--") { $args | skip 1 } else { $args }
	let pathish = ($script | str contains "/") or ($script | str contains "\\") or ($script | str starts-with ".")
	let resolved = if $pathish { $script } else { $env.FILE_PWD | path join $script }
	if not ($resolved | path exists) {
		print -e $"sayt --script: ($resolved) not found"
		exit 1
	}
	run-nu -I $env.FILE_PWD $resolved ...$args
}

# Dispatch a verb through the override chain:
# 1. .sayt.<verb>.nu script (per-verb file)
# 2. .sayt.nu script (if it defines "main <verb>")
# 3. Config-driven rules from say.<verb> in .say.* files / config.cue
def --wrapped run-verb [verb: string, ...args] {
	if ("--help" in $args) or ("-h" in $args) {
		run-nu $"($env.FILE_PWD)/sayt.nu" help $verb
		return
	}

	# Version pin: `say.self.version` overrides the invoked distribution;
	# re-exec through saytw and stop — the pinned version runs the verb.
	let config = try { load-config } catch { { say: {} } }
	let dist_version = open ($env.FILE_PWD | path join "VERSION") | str trim
	let target_version = $config.say?.self?.version? | default $dist_version
	if ($target_version != $dist_version) {
		re-exec-with-version $target_version ([$verb] ++ $args)
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

	# Layer 3: config-driven rules (rulemap.nu).
	rulemap run-rules $config $verb ...$args
}


