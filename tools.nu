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

def is-musl [] {
  if (sys host | get name) != 'Linux' {
    false
  } else {
    let matches = (glob /lib/ld-musl-*.so.*) ++ (glob /lib/ld-musl-*.so)
    ($matches | length) > 0
  }
}

def stub-path [name: string] {
  let base = (dirname $path_self | path join $"($name).toml")
  if (is-musl) {
    let musl = (dirname $path_self | path join $"($name).musl.toml")
    if ($musl | path exists) { $musl } else { $base }
  } else {
    $base
  }
}

def mise-bin [] {
  let is_windows = (sys host | get name) == 'Windows'
  let exe = if $is_windows { "mise.exe" } else { "mise" }
  let base = dirname $path_self
  let local = $base | path join $exe
  if ($local | path exists) {
    $local
  } else {
    let dirs = ls $base | where { |row| ($row.name | path basename) starts-with "mise-" } | get name | sort
    if ($dirs | is-empty) { "mise" } else { $dirs | last | path join $exe }
  }
}

export def --wrapped run-mise [...args] {
  let mise = mise-bin
  let trusted = $env.MISE_TRUSTED_CONFIG_PATHS? | default ""
  if (".mise.toml" | path exists) and ($trusted | is-empty) {
    ^$mise trust -y -a -q
  }
  vrun $mise ...$args
}

export def --wrapped run-cue [...args] {
  let stub = stub-path "cue"
  with-env { MISE_LOCKED: "0" } { run-mise tool-stub $stub ...$args }
}

export def --wrapped run-uvx [...args] {
  let stub = stub-path "uvx"
  with-env { MISE_LOCKED: "0" } { run-mise tool-stub $stub ...$args }
}

export def --wrapped run-docker [...args] {
  let stub = stub-path "docker"
  with-env { MISE_LOCKED: "0" } { run-mise tool-stub $stub ...$args }
}

export def --wrapped run-docker-compose [...args] {
  let stub = stub-path "docker"
  with-env { MISE_LOCKED: "0" } { run-mise tool-stub $stub compose ...$args }
}

export def --wrapped run-nu [...args] {
  let stub = stub-path "nu"
  with-env { MISE_LOCKED: "0" } { run-mise tool-stub $stub ...$args }
}
