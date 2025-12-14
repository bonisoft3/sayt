export def --wrapped vrun [--trail="\n", cmd, ...args] {
  let quoted_args = $args | each { |arg|
    if ($arg | into string | str contains ' ') { $arg | to nuon } else { $arg } }
  print -n $"($cmd) ($quoted_args | str join ' ')($trail)"
  $in | ^$cmd ...$args
}

const path_self = path self
export def --wrapped run-cue [...args] {
  let stub = dirname $path_self | path join "cue.toml"
  vrun mise tool-stub $stub ...$args
}

export def --wrapped run-uvx [...args] {
  let stub = dirname $path_self | path join "uvx.toml"
  vrun mise tool-stub $stub ...$args
}

export def --wrapped run-docker [...args] {
  let stub = dirname $path_self | path join "docker.toml"
  vrun mise tool-stub $stub ...$args
}

export def --wrapped run-docker-compose [...args] {
  let stub = dirname $path_self | path join "docker.toml"
  vrun mise tool-stub $stub compose ...$args
}

export def --wrapped run-nu [...args] {
  let stub = dirname $path_self | path join "nu.toml"
  vrun mise tool-stub $stub ...$args
}
