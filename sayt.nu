#!/usr/bin/env nu
use std log
use dind.nu
use tools.nu [run-cue run-docker run-docker-compose run-nu run-uvx vrun]

def --wrapped main [
	--help (-h),              # show this help message
	--directory (-d) = ".",   # directory where to run the command
	--install,                # install sayt binary to ~/.local/bin (Unix) or %LOCALAPPDATA%\Programs\sayt (Windows)
	--global (-g),            # with --install: install to /usr/local/bin (Unix) or C:\Program Files\sayt (Windows) for all users
	--commit,                 # add saytw and saytw.ps1 wrapper scripts to current directory and commit
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

	run-nu $"($env.FILE_PWD)/sayt.nu" $subcommand ...$args
}

def --wrapped vtr [...args: string] {
  try {
    run-uvx --offline vscode-task-runner ...$args
  } catch {
    run-uvx vscode-task-runner ...$args
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

# Installs runtimes and tools for the project
export def "main setup" [...args] { setup ...$args }

# Runs environment diagnostics for required tooling
export def --wrapped "main doctor" [
	--help (-h),
	...args: string
] {
	doctor ...$args
}

# Generates files according to SAY config rules
export def "main generate" [--force (-f), ...args] { generate --force=$force ...$args }

# Runs lint rules from the SAY configuration
export def "main lint" [...args] { lint ...$args }

# Runs the configured build task via vscode-task-runner
export def "main build" [...args] { vtr build ...$args }

# Runs the configured test task via vscode-task-runner
export def --wrapped "main test" [
	--help (-h),
	...args: string
] {
	vtr test ...$args
}

# Launches the develop docker compose stack
export def "main launch" [...args] { docker-compose-vrun develop ...$args }

# Runs the integrate docker compose workflow
#
# Extra flags are passed through to docker compose:
#   --pull always     Pull fresh base images
#   --no-cache        Build without Docker layer cache
#   --quiet-pull      Suppress pull progress output
export def "main integrate" [
	--no-cache        # Build without Docker layer cache
	...args           # Additional flags passed to docker compose up
] {
	# Clean slate: remove any leftover containers from previous runs
	run-docker-compose down -v --timeout 0 --remove-orphans

	# If --no-cache, build without cache first
	if $no_cache {
		dind-vrun docker compose build --no-cache integrate
	}

	# Run compose with dind environment and capture exit code
	docker-compose-vup integrate --abort-on-container-failure --exit-code-from integrate --force-recreate --build --renew-anon-volumes --remove-orphans --attach-dependencies ...$args
	let exit_code = $env.LAST_EXIT_CODE

	# Only cleanup on success - on failure, keep containers for inspection
	if $exit_code == 0 {
		run-docker-compose down -v --timeout 0 --remove-orphans
	} else {
		print -e "Integration failed. Containers left for inspection. Run 'docker compose logs' or 'docker compose down -v' when done."
		exit $exit_code
	}
}

# Builds release artifacts using the release task
export def "main release" [...args] { vtr setup-butler ...$args }

# Verifies release artifacts using the same release flow
export def "main verify" [...args] { vtr setup-butler ...$args }

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

	let is_windows = (sys host | get name) == 'Windows'
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
	if ((sys host | get name) == 'Windows') {
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

# Downloads saytw and saytw.ps1 wrapper scripts to current directory and commits them
def commit-wrappers [] {
	let version = $env.SAYT_VERSION? | default "v0.0.13"
	let base_url = $"https://raw.githubusercontent.com/bonitao/sayt/($version)"

	# Verify we're in a git repository
	if not (".git" | path exists) and (do { git rev-parse --git-dir } | complete | get exit_code) != 0 {
		print -e "Error: Not in a git repository. Run this from a git-tracked directory."
		exit 1
	}

	print $"Downloading wrapper scripts \(($version)\)..."

	# Download saytw (Unix)
	let saytw_url = $"($base_url)/saytw"
	http get $saytw_url | save -f saytw
	if ((sys host | get name) != 'Windows') {
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

# A path relative-to that works with sibilings directorys like python relpath.
def "path relpath" [base: string] {
	let target_parts = $in | path expand | path split
	let start_parts = $base | path expand | path split

	let common_len = ($target_parts | zip $start_parts | take while { $in.0 == $in.1 } | length)
	let ups = ($start_parts | length) - $common_len

	let result = (if $ups > 0 { 1..$ups | each { ".." } } else { [] }) | append ($target_parts | skip
		$common_len)

	if ($result | is-empty) { "." } else { $result | path join }
}

def load-config [--config=".say.{cue,yaml,yml,json,toml,nu}"] {
	# Step 1: Find and merge all .say.* config files
	let default = $env.FILE_PWD | path join "config.cue" | path relpath $env.PWD
	let config_files = glob $config | each { |f| basename $f } | append $default
  let nu_file = $config_files | where ($it | str ends-with ".nu") | get 0?
  let cue_files = $config_files | where not ($it | str ends-with ".nu")
	# Step 2: Generate merged configuration
	let nu_result = if ($nu_file | is-empty) {
		vrun --trail="| " echo
	} else {
		vrun --trail="| " --envs { "NU_LIB_DIRS": $env.FILE_PWD } nu -n $in
	}
  let config = $nu_result | run-cue export ...$cue_files --out yaml - | from yaml
	return $config
}

def generate [--config=".say.{cue,yaml,yml,json,toml,nu}", --force (-f), ...files] {
	let config = load-config --config $config
	# If files are provided,  filter rules based on their outputs matching the files
	let rules = if ($files | is-empty) {
		$config.say.generate.rules?
	} else {
		# Convert files list to a set for O(1) lookup
		let file_set = $files | reduce -f {} { |file, acc| $acc | upsert $file true }
		$config.say.generate.rules? | where { |rule|
			$rule.cmds | any { |cmd|
				$cmd.outputs? | default [] | any { |output| $file_set | get $output | default false }
			}
		}
	} | default $config.say.generate.rules  # optimistic run of all rules if no output found

	let rules = $rules | default []
	for rule in $rules {
		let cmds = $rule.cmds? | default []
		for cmd in $cmds {
			let do = $"do { ($cmd.do) } ($cmd.args? | default "")"
			let withenv = $"with-env { SAY_GENERATE_ARGS_FORCE: ($force) }"
			let use = if ($cmd.use? | is-empty) { "" } else { $"use ($cmd.use);" }
			run-nu -I ($env.FILE_PWD | path relpath $env.PWD) -c $"($use)($withenv) { ($do) }"
		}
	}

	$files | each { |file| if (not ($file | path exists)) {
		print -e $"Failed to generate ($file)"
		exit -1
	} }
	return
}

def lint [--config=".say.{cue,yaml,yml,json,toml,nu}", ...args] {
	let config = load-config --config $config
	let rules = $config.say.lint.rules? | default []
	for rule in $rules {
		let cmds = $rule.cmds? | default []
		for cmd in $cmds {
			let do = $"do { ($cmd.do) } ($cmd.args? | default "")"
			let use = if ($cmd.use? | is-empty) { "" } else { $"use ($cmd.use);" }
			run-nu -I ($env.FILE_PWD | path relpath $env.PWD) -c $"($use) ($do)"
		}
	}
	return
}

def setup [...args] {
	if ('.mise.toml' | path exists) {
		vrun mise trust -y -a -q
		with-env { MISE_LOCKED: null } { vrun mise install }
		# Preload vscode-task-runner in cache so uvx works offline later
		run-uvx vscode-task-runner -h | ignore
	}
	# --- Recursive call section (remains the same) ---
	if ('.sayt.nu' | path exists) {
		run-nu '.sayt.nu' setup ...$args
	}
}

def --wrapped docker-compose-vup [--progress=auto, target, ...args] {
	dind-vrun docker compose up $target ...$args
}
def --wrapped docker-compose-vrun [--progress=auto, target, ...args] {
	run-docker-compose down -v --timeout 0 --remove-orphans $target
	dind-vrun docker compose --progress=($progress) run --build --service-ports $target ...$args
}

def --wrapped dind-vrun [cmd, ...args] {
	let host_env = dind env-file --socat
	let socat_container_id = $host_env | lines | where $it =~ "SOCAT_CONTAINER_ID" | split column "=" | get ($in | columns | last) | first
	vrun --envs { "HOST_ENV": $host_env } $cmd ...$args
	run-docker rm -f $socat_container_id
}

def doctor [...args] {
	let envs = [ {
		"pkg": (check-installed mise scoop),
		"cli": (check-all-of-installed cue gomplate),
		"ide": (check-installed vtr),
		"cnt": (check-installed docker),
		"k8s": (check-all-of-installed kind skaffold),
		"cld": (check-installed gcloud),
		"xpl": (check-installed crossplane)
	} ]
	print "Tooling Checks:"
	print ($envs | update cells { |it| convert-bool-to-checkmark $it } | first | transpose key value)

	print ""
	print "Health Checks:"
	let dns = {
		"dns-google": (check-dns "google.com"),
		"dns-github": (check-dns "github.com")
	}
	print ($dns
	| transpose key value
	| update value { |row| convert-bool-to-checkmark $row.value })

	if ($dns | values | any { |v| $v == false }) {
		error make { msg: "DNS resolution failed. Network connectivity issues detected." }
	}
}

def convert-bool-to-checkmark [ it: bool ] {
  if $it { "✓" } else { "✗" }
}

def check-dns [domain: string] {
  try {
    (http head $"https://($domain)" | is-not-empty)
  } catch {
    false
  }
}

def check-all-of-installed [ ...binaries ] {
  $binaries | par-each { |it| check-installed $it } | all { |el| $el == true }
}
def check-installed [ binary: string, windows_binary: string = ""] {
	if ((sys host | get name) == 'Windows') {
		if ($windows_binary | is-not-empty) {
			(which $windows_binary) | is-not-empty
		} else {
			(which $binary) | is-not-empty
		}
	} else {
		(which $binary) | is-not-empty
	}
}
