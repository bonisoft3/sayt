def format-export [name: string, value: string] {
  let is_windows = (sys host | get name) == 'Windows'
  let has_newline = $value | str contains (char nl)

  if $is_windows {
    if $has_newline {
      let escaped = $value | str replace -a "'" "''"
      return $"$env:($name) = @'
($escaped)
'@"
    } else {
      return $"$env:($name) = ($value)"
    }
  }

  if $has_newline {
    let escaped = $value
      | str replace -a "\\" "\\\\"
      | str replace -a "\"" "\\\""
      | str replace -a "$" "\\$"
      | str replace -a (char nl) "\\n"
    return $"export ($name)=$(printf '%s' ($escaped))"
  } else {
    return $"export ($name)=($value)"
  }
}

export def --wrapped vrun [--trail="\n", --envs: record = {}, cmd, ...args] {
  let quoted_args = $args | each { |arg|
    if ($arg | into string | str contains ' ') { $arg | to nuon } else { $arg } }
  let env_pairs = if ($envs | is-empty) { [] } else { $envs | transpose name value }
  if ($env_pairs | is-not-empty) {
    $env_pairs | each { |row| print (format-export $row.name $row.value) }
  }
  with-env $envs {
    print -n $"($cmd) ($quoted_args | str join ' ')($trail)"
    $in | ^$cmd ...$args
  }
}

export def vexport [name: string, value: string] {
  load-env { ($name): ($value) }
  print (format-export $name $value)
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
