#!/usr/bin/env nu
use std log
use std repeat
use dind.nu

def --wrapped main [
   --help (-h),  # show this help message
   --directory (-d) = ".",  # directory where to run the command
	subcommand?: string, ...args] {
	cd $directory
  let subcommands = (scope commands | where name =~ "^main " | get name | each { |cmd| $cmd | str replace "main " "" })
	if $help or not ($subcommand in $subcommands) {
		help main
	} else {
		vrun nu $"($env.FILE_PWD)/sayt.nu" $subcommand ...$args
	}
}



# Print external command and execute it. Only for external commands.
def --wrapped vrun [--trail="\n", cmd, ...args] {
  let quoted_args = $args | each { |arg|
		if ($arg | into string | str contains ' ') { $arg | to nuon } else { $arg } }
  print -n $"($cmd) ($quoted_args | str join ' ')($trail)"
  $in | ^$cmd ...$args
}

def --wrapped vtr [...args: string] {
  try {
    vrun mise x -- uvx --offline vscode-task-runner ...$args
  } catch {
    vrun mise x -- uvx vscode-task-runner ...$args
  }
}

def --wrapped "main setup" [...args] { setup ...$args }
def --wrapped "main doctor" [...args] { setup ...$args }
def --wrapped "main generate" [--force (-f), ...args] { generate --force=$force ...$args }
def --wrapped "main lint" [...args] { lint ...$args }
def --wrapped "main build" [...args] { vtr build ...$args }
def --wrapped "main test" [...args] { vtr test ...$args }
def --wrapped "main launch" [...args] { docker-compose-vrun develop ...$args }
def --wrapped "main integrate" [...args] { docker-compose-vrun --progress=plain integrate ...$args }
def --wrapped "main release" [...args] { vtr setup-butler ...$args }
def --wrapped "main verify" [...args] { vtr setup-butler ...$args }

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
	let nu_result = if ($nu_file | is-empty) { vrun --trail="| " echo } else { with-env { NU_LIB_DIRS: $env.FILE_PWD } { vrun --trail="| " nu -n $in } }
  let config = $nu_result | vrun cue export ...$cue_files --out yaml - | from yaml
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

	$rules | each { |rule|
		$rule.cmds? | each { |cmd|
			let do = $"do { ($cmd.do) } ($cmd.args? | default "")"
			let withenv = $"with-env { SAY_GENERATE_ARGS_FORCE: ($force) }"
			let use = if ($cmd.use? | is-empty) { "" } else { $"use ($cmd.use);" }
			vrun nu -I ($env.FILE_PWD | path relpath $env.PWD) -c $"($use)($withenv) { ($do) }"
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
	$config.say.lint.rules? | each { |rule|
		$rule.cmds? | each { |cmd|
			let do = $"do { ($cmd.do) } ($cmd.args? | default "")"
			let use = if ($cmd.use? | is-empty) { "" } else { $"use ($cmd.use);" }
			vrun nu -I ($env.FILE_PWD | path relpath $env.PWD) -c $"($use) ($do)"
		}
	}
	return
}

def setup [...args] {
	if ('.mise.toml' | path exists) {
		vrun mise trust -q
		vrun mise install
		# Preload vscode-task-runner in cache so uvx works offline later
		vrun mise x -- uvx vscode-task-runner -h | ignore
	}
	# --- Recursive call section (remains the same) ---
	if ('.sayt.nu' | path exists) {
		vrun nu '.sayt.nu' setup ...$args
	}
}

def --wrapped docker-compose-vrun [--progress=auto, target, ...args] {
	vrun docker compose down -v --timeout 0 --remove-orphans $target
	dind-vrun docker compose --progress=($progress) run --build --service-ports $target ...$args
}

def --wrapped dind-vrun [cmd, ...args] {
	let host_env = dind env-file --socat
	let socat_container_id = $host_env | lines | where $it =~ "SOCAT_CONTAINER_ID" | split column "=" | get column2 | first
	with-env { HOST_ENV: $host_env } {
		vrun $cmd ...$args
		vrun docker rm -f $socat_container_id
	}
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
	$envs | update cells { |it| convert-bool-to-checkmark $it }
}

def convert-bool-to-checkmark [ it: bool ] {
  if $it { "✓" } else { "✗" }
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

