#!/usr/bin/env nu
use std log
use std repeat
use dind.nu

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
		vrun pkgx pkgx@1.5.0 +pypa.github.io/pipx pipx run -q $pkg ...$args
	}
}
def --wrapped vtr [...args: string] {
  pipx vscode-task-runner ...$args
}

def --wrapped "main vet" [...args] { vet ...$args }
def --wrapped "main setup" [...args] { setup ...$args }
def --wrapped  "main doctor" [...args] { doctor ...$args }
def --wrapped "main build" [...args] { vtr build ...$args }
def --wrapped "main test" [...args] { vtr test ...$args }
def --wrapped "main develop" [...args] { docker-compose-vrun develop ...$args }
def --wrapped "main integrate" [...args] { docker-compose-vrun --progress=plain integrate ...$args }
def --wrapped "main setup-butler" [...args] { vtr setup-butler ...$args }

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
        # --- Non-Windows Section ---
        if ((sys host | get name) != 'Windows') {

            # --- Handle 'dependencies' (logic remains the same) ---
            let dependencies_raw = (open .pkgx.yaml | get -i dependencies);
            let dependencies_processed = (
                if (($dependencies_raw | describe) == 'string') {
                    $dependencies_raw | split row " "
                } else if (($dependencies_raw | describe) == 'list') {
                    $dependencies_raw
                } else {
                    []
                }
            );
            $dependencies_processed
            | flatten
            | filter { $in != "" }
            | par-each { |it| vrun pkgx pkgx@1.5.0 install $it };

            # --- Handle 'env.SAY_INSTALL_GITHUB_RELEASE' ---
            # 1. Get value, default to empty list [] if null
            let gh_release_raw = (
                open .pkgx.yaml
                | get -i env.SAY_INSTALL_GITHUB_RELEASE
                | default []
            );
            # 2. Ensure result is list<string> (split if string, pass if list)
            let gh_release_processed = (
                if (($gh_release_raw | describe) == 'string') {
                    # Split non-empty string, otherwise return empty list
                    if ($gh_release_raw == "") { [] } else { $gh_release_raw | split row " " }
                } else {
                    # Assume it's already a list (or empty list)
                    $gh_release_raw
                }
            );
            # 3. Pipe the guaranteed list
            $gh_release_processed
            | flatten
            | filter { $in != "" }
            | par-each { |it| curl -Ls $"curl https://i.jpillora.com/($it)!" | pkgx pkgx@1.5.0 bash@5.2.37 };

        # --- Windows Section ---
        } else {
            # --- Handle 'env.SAY_SCOOP_BUCKET_ADD' ---
            let scoop_bucket_raw = (
                open .pkgx.yaml
                | get -i env.SAY_SCOOP_BUCKET_ADD
                | default []
            );
            let scoop_bucket_processed = (
                if (($scoop_bucket_raw | describe) == 'string') {
                    if ($scoop_bucket_raw == "") { [] } else { $scoop_bucket_raw | split row " " }
                } else {
                    $scoop_bucket_raw
                }
            );
            $scoop_bucket_processed
            | flatten
            | filter { $in != "" }
            | par-each { |it| vrun scoop bucket add $it };

            # --- Handle 'env.SAY_SCOOP_INSTALL' ---
            let scoop_install_raw = (
                open .pkgx.yaml
                | get -i env.SAY_SCOOP_INSTALL
                | default []
            );
            let scoop_install_processed = (
                if (($scoop_install_raw | describe) == 'string') {
                    if ($scoop_install_raw == "") { [] } else { $scoop_install_raw | split row " " }
                } else {
                    $scoop_install_raw
                }
            );
            $scoop_install_processed
            | flatten
            | filter { $in != "" }
            | par-each { |it| vrun scoop install $it };
        }
    }
    # --- Recursive call section (remains the same) ---
    if ('.sayt.nu' | path exists) {
        vrun nu '.sayt.nu' setup ...$args
    }
}

def --wrapped docker-compose-vrun [--progress=auto, target, ...args] {
	vrun docker compose down --remove-orphans $target
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



