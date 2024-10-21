#!/usr/bin/env nu
use std log

def --wrapped main [
   --directory (-d) = ".",  # directory where to run the command
   subcommand?: string, ...args] {
   if $subcommand == null {
     help sayt
   } else {
     sayt --directory $directory $subcommand ...$args
   }
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

def chat [...args] {
	if ($env.GROQ_API_KEY | is-empty) and ($args | is-empty) {
		log warning "GROQ_API_KEY is empty and no arguments provided"
		exit 1
	} else if ($args | is-empty) {
		aider --model groq/llama-3.1-70b-versatile
	} else {
		aider ...$args
	}
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

def test [...args] {
	if ((sys host | get name) == 'Windows') {
		$env.PATH = ($env.PATH | prepend "C:/Program Files")
	}
	vtr test ...$args
}
def build [...args] { vtr build ...$args }
def develop [...args] { vrun docker compose run --service-ports --build develop ...$args }
def integrate [...args] {
	if ((sys host | get name) == 'Darwin') {
		if not (^find $"($env.FILE_PWD)/../.." -xattr | is-empty) {
			log warning "Found extended attributes (xattr) which breaks nested docker cache"
		}
	}
	let repo_root = echo $env.FILE_PWD | path join .. .. | path expand
	let compose_yaml = echo . | path join "plugins" "devserver" "compose.yaml"
	let compose_yaml_abs = echo $repo_root | path join $compose_yaml
	let dockerfile = echo $env.PWD | path relative-to $repo_root | path join Dockerfile
  vrun docker compose -f $compose_yaml_abs run --build develop env $"INTEGRATE_DOCKERFILE=($dockerfile)" docker compose  -f $compose_yaml build integrate ...$args
}
def preview [...args] { vrun skaffold dev -p preview }

def --wrapped vtr [...args: string] {
	pipx vscode-task-runner ...$args
}

def --wrapped aider [...args: string] {
	pipx aider-chat ...$args
}


def sh [...command: string] {
  if ((sys host | get name) == 'Windows') {
    pwsh.exe -c ...$command
  } else {
    bash -c 'exec "$@"' -- ...$command
  }
}

def sayt [
   --directory (-d) = ".",  # directory where to run the command
   subcommand: string, ...args] {
  cd $directory
  match $subcommand {
    "setup" => { setup ...$args },
    "doctor" => { doctor ...$args },
    "chat" => { chat ...$args },
    "vet" => { vet ...$args },
    "build" => { build ...$args },
    "test" => { test ...$args },
    "develop" => { develop ...$args },
    "integrate" => { integrate ...$args },
    "preview" => { preview ...$args },
    "verify" => { verify ...$args },
    "stage" => { stage ...$args },
    "loadtest" => { loadtest ...$args },
    "publish" => { publish ...$args },
    "observe" => { observe ...$args },
    _ => {
       $"subcommand ($subcommand) not found"
    }
  }
}
