# Secrets must never reach stdout/stderr/CI logs. vrun's export echo is purely
# diagnostic (the real env is applied via `with-env`, not these lines), so
# redacting the value here has no functional effect — it only stops the
# HOST_ENV projection (DOCKER_AUTH_CONFIG registry creds, KUBECONFIG_DATA
# client keys, DEPOT_TOKEN, …) from being printed verbatim.
export def is-secret-key [name: string]: nothing -> bool {
  let n = ($name | str uppercase)
  let exact = ["HOST_ENV" "DOCKER_AUTH_CONFIG" "KUBECONFIG_DATA"]
  ($n in $exact) or ($n =~ "TOKEN|SECRET|PASSWORD|CREDENTIAL|PRIVATE_KEY|_AUTH|AUTH_")
}

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

# Run an external command, streaming stdout/stderr live, and return its exit
# code. Bare `^cmd` raises mid-block on non-zero exit, and `do { ^cmd } |
# complete` buffers everything until the command exits — killing live
# `--progress=plain` output during long builds. try/catch is the streaming
# equivalent of `complete`.
export def --wrapped run-live [cmd, ...args] {
	try { ^$cmd ...$args; 0 } catch { |err| $err.exit_code }
}

# run-live's contract over vrun: stream with the env/cmd preamble and
# return the exit code instead of raising. Callers that need the
# external's stdout keep plain vrun (its pipeline output is the
# command's output — a capture wrapper would discard it).
export def --wrapped vrun-live [--envs: record = {}, cmd, ...args] {
	try { vrun --envs $envs $cmd ...$args; 0 } catch { |err| $err.exit_code }
}

# Diagnostics go to stderr: callers capture stdout for the command's output alone.
export def --wrapped vrun [--trail="\n", --envs: record = {}, cmd, ...args] {
  let quoted_args = $args | each { |arg|
    if ($arg | into string | str contains ' ') { $arg | to nuon } else { $arg } }
  let env_pairs = if ($envs | is-empty) { [] } else { $envs | transpose name value }
  if ($env_pairs | is-not-empty) {
    $env_pairs | each { |row|
      let shown = if (is-secret-key $row.name) { "***redacted***" } else { $row.value }
      print -e (format-export $row.name $shown)
    }
  }
  with-env $envs {
    print -e -n $"($cmd) ($quoted_args | str join ' ')($trail)"
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

export def mise-bin [] {
  let bootstrapped = $env.SAYT_MISE_BIN? | default ""
  if ($bootstrapped | is-not-empty) {
    if not ($bootstrapped | path exists) { error make {msg: $"Sayt's Mise executable is missing: ($bootstrapped)"} }
    return $bootstrapped
  }
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
  let found = which mise
  if ($found | is-empty) { error make {msg: "Mise is unavailable; start Sayt through saytw or sayt.sh"} }
  $found | first | get path
}

export def mise-env []: nothing -> record {
  let mise = mise-bin
  let searched = [($mise | path dirname)] ++ $env.PATH
  let paths = if $nu.os-info.name == "windows" {
    {Path: ($searched | str join (char esep))}
  } else {
    {PATH: $searched}
  }
  {SAYT_MISE_BIN: $mise} | merge $paths
}

export def --wrapped run-mise [...args] {
  with-env (mise-env) {
    hide-env -i MISE_LOCKED
    mise-trust $env.SAYT_MISE_BIN
    # Bootstrap stubs and explicit lock updates precede a usable project lock.
    let unlocked = ($args.0? in ["tool-stub" "lock"])
    with-env (if $unlocked { {MISE_LOCKED: "0"} } else { {} }) {
      vrun $env.SAYT_MISE_BIN ...$args
    }
  }
}

# run-mise's trust handling with vrun-live's contract, plus an env overlay.
export def --wrapped run-mise-live [--envs: record = {}, ...args] {
  with-env (mise-env) {
    hide-env -i MISE_LOCKED
    mise-trust $env.SAYT_MISE_BIN
    let unlocked = ($args.0? in ["tool-stub" "lock"])
    with-env (if $unlocked { {MISE_LOCKED: "0"} } else { {} }) {
      vrun-live --envs $envs $env.SAYT_MISE_BIN ...$args
    }
  }
}

# mise reads the cwd's config, so an untrusted .mise.toml blocks any
# invocation — including a tool-stub, whose own path is not the config.
def mise-trust [mise: string] {
  let trusted = $env.MISE_TRUSTED_CONFIG_PATHS? | default ""
  if (".mise.toml" | path exists) and ($trusted | is-empty) {
    ^$mise trust -y -a -q
  }
}

export def --wrapped run-cue [...args] {
  let stub = stub-path "cue"
  run-mise tool-stub $stub ...$args
}

export def --wrapped run-docker [...args] {
  let stub = stub-path "docker"
  run-mise tool-stub $stub ...$args
}

# See compose.toml for why compose is pinned rather than reached through
# `docker compose`.
export def compose-stub []: nothing -> string {
  stub-path "compose"
}

export def --wrapped run-docker-compose [...args] {
  # COMPOSE_BAKE=true → compose builds via `buildx bake`: parallel
  # cross-service builds + better cache sharing.
  with-env { COMPOSE_BAKE: "true" } { run-mise tool-stub (compose-stub) ...$args }
}

export def --wrapped run-git-cliff [...args] {
  let stub = stub-path "git-cliff"
  run-mise tool-stub $stub ...$args
}

export def --wrapped run-goreleaser [...args] {
  let stub = stub-path "goreleaser"
  run-mise tool-stub $stub ...$args
}

export def --wrapped run-nu [...args] {
	let stub = stub-path "nu"
	run-mise tool-stub $stub ...$args
}

export def --wrapped main [tool: string, ...args] {
	match $tool {
		"cue" => { run-cue ...$args }
		"docker" => { run-docker ...$args }
		"compose" => { run-docker-compose ...$args }
		"git-cliff" => { run-git-cliff ...$args }
		"goreleaser" => { run-goreleaser ...$args }
		"nu" => { run-nu ...$args }
		"mise" => { run-mise ...$args }
		_ => { error make {msg: $"sayt tools: unsupported tool ($tool)"} }
	}
}
