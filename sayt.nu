#!/usr/bin/env nu
use std log
use std repeat

def --wrapped main [
   --help (-h),  # show this help message
   --directory (-d) = ".",  # directory where to run the command
	subcommand?: string, ...args] {
	cd $directory
	if $subcommand == null or $help {
		help main
	} else {
		vrun nu $"($env.FILE_PWD)/sayt.nu" $subcommand ...$args
	}
}

# Print external command and execute it. Only for external commands.
def --wrapped vrun [cmd, ...args] {
  print $"($cmd) ($args | str join ' ')"
  ^$cmd ...$args
}

def pipx [pkg, ...args] {
	if ((sys host | get name) == 'Windows') {
		vrun pipx run -q $pkg ...$args
	} else {
		vrun pkgx +pypa.github.io/pipx pipx run -q $pkg ...$args
	}
}
def --wrapped vtr [...args: string] {
  pipx vscode-task-runner ...$args
}

def --wrapped "main vet" [...args] { setup ...$args }
def --wrapped "main setup" [...args] { setup ...$args }
def --wrapped  "main doctor" [...args] { doctor ...$args }
def --wrapped "main build" [...args] { vtr build ...$args }
def --wrapped "main test" [...args] { vtr test ...$args }
def --wrapped "main develop" [...args] { vrun docker compose run --service-ports --build develop ...$args }
def --wrapped "main integrate" [...args] { integrate ...$args }

def vet [...files] {
	let cue_files = if ($files | is-empty) {
		glob **/*.cue
	} else {
		$files | each { |file|
			$"($file).cue"
		}
	}

	# Filter and process .cue files
	$cue_files | each { |cue_file|
		let base_name = $cue_file | path parse | get stem
		let parent_dir = $cue_file | path dirname
		let sibling_file = $parent_dir | path join $base_name

		if ($sibling_file | path exists) {
			let sibling_extension = $sibling_file | path parse | get extension
			
			# Export if files were explicitly provided
			if not ($files | is-empty) {
				if $sibling_extension == "" {
					vrun cue export $cue_file --out text | str substring ..-1 | save --force $sibling_file
				} else {
					vrun cue export $cue_file --force --outfile $sibling_file
				}
			}

			if $sibling_extension == "" {
				vrun cue vet $cue_file text: $sibling_file
			} else {
				vrun cue vet $cue_file $sibling_file
			}
		}
	}
	return
}

def setup [...args] {
	if ('.pkgx.yaml' | path exists) {
		if ((sys host | get name) != 'Windows') {
			open .pkgx.yaml | get -i dependencies | filter { is-not-empty } | split row " " | par-each { |it| vrun pkgx install $it }
			open .pkgx.yaml | get -i env.SAY_INSTALL_GITHUB_RELEASE | filter { is-not-empty } | split row " " | par-each { |it| curl -Ls $"($it)!" | bash }
		} else {
			open .pkgx.yaml | get -i env.SAY_SCOOP_BUCKET_ADD | filter { is-not-empty } | split row " " | par-each { |it| vrun scoop bucket add $it }
			open .pkgx.yaml | get -i env.SAY_SCOOP_INSTALL | filter { is-not-empty } | split row " " | par-each { |it| vrun scoop install $it }
		}
	}
	if (('.sayt.nu' | path exists) and (open '.sayt.nu' | str contains 'def main [') and (nu .sayt.nu --help | str contains '.sayt.nu setup')) {
		nu '.sayt.nu' setup ...$args
	}
}

def integrate [...args] {
	if ((sys host | get name) == 'Darwin') {
		if not (^find $"($env.FILE_PWD)/../.." -xattr | is-empty) {
			log warning "Found extended attributes (xattr) which breaks nested docker cache"
		}
	}
	let repo_root = echo $env.FILE_PWD | path join .. .. | path expand
	log info $repo_root
	log info $env.PWD
	let repo_root_relative = ".." | repeat ($env.PWD | path relative-to $repo_root | path split| length) | path join
	let compose_yaml = $repo_root_relative | path join "plugins" "devserver" "compose.yaml"
	let compose_yaml_linux = $compose_yaml | path expand | path relative-to $repo_root | str replace -a "\\" "/"
	let dockerfile = echo $env.PWD | path relative-to $repo_root | path join Dockerfile 
	let dockerfile_linux = $dockerfile | str replace -a "\\" "/"
  vrun docker compose -f $compose_yaml run --remove-orphans --build develop env $"INTEGRATE_DOCKERFILE=($dockerfile_linux)" docker compose  -f $compose_yaml_linux build integrate ...$args
}

def doctor [...args] {
	let envs = [ {
		"pkg": (check-installed pkgx scoop),
		"cli": (check-all-of-installed cue aider),
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



