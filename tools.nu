def format-export [name: string, value: string] {
  let is_windows = $nu.os-info.name == 'windows'
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

const path_self = path self

def is-glibc [] {
  ["/lib64/ld-linux-x86-64.so.2" "/lib/ld-linux-aarch64.so.1" "/lib/ld-linux-armhf.so.3"] | any { |p| $p | path exists }
}

def stub-path [name: string] {
  let dir = ($path_self | path dirname)
  let musl = ($dir | path join $"($name).musl.toml")
  let glibc = ($dir | path join $"($name).toml")
  if (is-glibc) or not ($musl | path exists) { $glibc } else { $musl }
}

def mise-bin [] {
  let is_windows = $nu.os-info.name == 'windows'
  let exe = if $is_windows { "mise.exe" } else { "mise" }
  let base = $path_self | path dirname
  # 1. Check for mise binary next to tools.nu
  let local = $base | path join $exe
  if ($local | path exists) { return $local }
  # 2. Check for mise-* versioned directory next to tools.nu
  let dirs = ls $base | where { |row| ($row.name | path basename) starts-with "mise-" } | get name | sort
  if ($dirs | is-not-empty) { return ($dirs | last | path join $exe) }
  # 3. Check sayt cache directories (where sayt.sh installs mise)
  let cache_dir = if $is_windows {
    $env.LOCALAPPDATA? | default "" | path join "sayt"
  } else if ((uname | get kernel-name) == "Darwin") {
    $env.HOME | path join "Library" "Caches" "sayt"
  } else {
    $env.XDG_CACHE_HOME? | default ($env.HOME | path join ".cache") | path join "sayt"
  }
  if ($cache_dir | path exists) {
    let cache_dirs = ls $cache_dir | where { |row| ($row.name | path basename) starts-with "mise-" } | get name | sort
    if ($cache_dirs | is-not-empty) { return ($cache_dirs | last | path join $exe) }
  }
  # 4. Fall back to PATH
  "mise"
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

export def --wrapped run-docker [...args] {
  let stub = stub-path "docker"
  with-env { MISE_LOCKED: "0" } { run-mise tool-stub $stub ...$args }
}

export def --wrapped run-docker-compose [...args] {
  let stub = stub-path "docker"
  # COMPOSE_BAKE=true → compose builds via `buildx bake`: parallel
  # cross-service builds + better cache sharing.
  with-env { MISE_LOCKED: "0", COMPOSE_BAKE: "true" } { run-mise tool-stub $stub compose ...$args }
}

export def --wrapped run-git-cliff [...args] {
  let stub = stub-path "git-cliff"
  with-env { MISE_LOCKED: "0" } { run-mise tool-stub $stub ...$args }
}

export def --wrapped run-goreleaser [...args] {
  let stub = stub-path "goreleaser"
  with-env { MISE_LOCKED: "0" } { run-mise tool-stub $stub ...$args }
}

export def --wrapped run-task [...args] {
  let stub = stub-path "task"
  # Put mise's own directory on PATH so commands inside Taskfiles
  # (e.g., `mise x -- pnpm build`) can find the mise binary.
  # PATH stays a list — string-interpolating $env.PATH would render
  # `[entry1, entry2, ...]` literally (nu list display form), which
  # tools that split PATH on `:` parse as garbage entries with
  # brackets/commas and downstream child-process spawns (notably
  # pnpm postinstall scripts) silently abort with exit -2.
  let mise_dir = (mise-bin | path dirname)
  with-env { MISE_LOCKED: "0", PATH: ([$mise_dir] ++ $env.PATH) } { run-mise tool-stub $stub ...$args }
}

export def --wrapped run-nu [...args] {
  let stub = stub-path "nu"
  with-env { MISE_LOCKED: "0" } { run-mise tool-stub $stub ...$args }
}

