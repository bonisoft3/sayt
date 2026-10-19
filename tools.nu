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

# How much a long command prints. `verbose` streams its output live, `normal`
# shows the command, a heartbeat and a verdict and keeps the output in a log,
# `quiet` prints nothing unless it fails. `sayt -v`/`-q` sets SAYT_VERBOSITY
# once and every nested sayt process inherits it; unset, a terminal or CI
# (whose log is the only record once the job ends) is verbose and anything
# else (an agent's tool call, whose whole output becomes context) is normal.
export def verbosity []: nothing -> string {
	let level = ($env.SAYT_VERBOSITY? | default "")
	if $level in ["quiet" "normal" "verbose"] { return $level }
	if ($level | is-not-empty) { error make {msg: $"SAYT_VERBOSITY is quiet, normal or verbose, not ($level)"} }
	if (is-terminal --stdout) or ($env.CI? | is-not-empty) { "verbose" } else { "normal" }
}

# Run an external command and return its exit code. Verbose streams it
# straight through: bare `^cmd` raises mid-block on non-zero exit, and
# `do { ^cmd } | complete` buffers everything until the command exits, so
# try/catch is the unbuffered equivalent of `complete`. Below verbose,
# run-logged keeps the output.
export def --wrapped run-live [cmd, ...args] {
	run-named (command-name $cmd $args) $cmd $args
}

# run-live with the verdict's name given. Not --wrapped, so the command's own
# flags (a `--name`, say) stay its own.
export def run-named [name: string, cmd, args: list]: nothing -> int {
	if (verbosity) == "verbose" {
		try { ^$cmd ...$args; 0 } catch { |err| $err.exit_code }
	} else {
		run-logged $name $cmd $args
	}
}

# What a verdict calls a command: the tool under a mise wrapper and its first
# two words that are neither flags nor a flag's value, so `mise exec -- task
# -t .bayt/Taskfile.yml bayt:test` reads `task bayt:test`.
def command-name [cmd, args: list]: nothing -> string {
	let given = ([$cmd ...$args] | each { into string })
	# A tool by its name, not its file: Windows runs mise as mise.exe or a .cmd shim.
	let tool = { |w| $w | path basename | str replace -r '(?i)\.(exe|cmd|bat)$' '' }
	let inner = if (do $tool $given.0) != "mise" { [] } else {
		match $given.1? {
			"exec" => ($given | skip 2 | skip while { |w| $w != "--" } | skip 1)
			"tool-stub" => ($given | skip 3 | prepend ($given.2? | default "" | path basename | str replace -r '(\.musl)?\.toml$' ''))
			_ => ($given | skip 1)
		}
	}
	let words = if ($inner | is-empty) { $given } else { $inner }
	# In `$words | skip 1`, the word before item i is $words.i.
	let rest = ($words | skip 1 | enumerate | where { |w|
		not ($w.item | str starts-with "-") and not ($words | get $w.index | str starts-with "-")
	} | get item | first 2 | each { path basename })
	[(do $tool $words.0) ...$rest] | str join " "
}

# run-live's contract over vrun: the env/cmd preamble, then run-live under
# the env overlay. Callers that need the external's stdout keep plain vrun
# (its pipeline output is the command's output — a capture wrapper would
# discard it).
export def --wrapped vrun-live [--envs: record = {}, cmd, ...args] {
	vrun-named (command-name $cmd $args) $envs $cmd $args
}

def vrun-named [name: string, envs: record, cmd, args: list]: nothing -> int {
	if (verbosity) != "quiet" { print-preamble $envs $cmd $args "\n" }
	with-env $envs { run-named $name $cmd $args }
}

# The log lives in SAYT_LOG_DIR, one private temp directory per sayt run. A
# failure prints all of it: sayt does not guess which lines name the failure.
def run-logged [name: string, cmd, args: list]: nothing -> int {
	let normal = ((verbosity) == "normal")
	let dir = ($env.SAYT_LOG_DIR? | default (mktemp -d -t sayt.XXXXXX))
	mkdir $dir
	let log = (mktemp -p $dir --suffix .log $"($cmd | path basename).XXXXXX")
	let started = (date now)
	let elapsed = {|| (date now) - $started | format duration sec | str replace -r '\.\d+' '' }
	let every = ($env.SAYT_HEARTBEAT_SECS? | default "60" | into int | into duration --unit sec)
	let beat = if $normal {
		job spawn { loop { sleep $every; print -e $"… ($name) still running \((do $elapsed), log: ($log)\)" } }
	}
	let code = (try { ^$cmd ...$args o+e> $log; 0 } catch { |err| $err.exit_code })
	if $beat != null { job kill $beat }
	if $code != 0 {
		open --raw $log | print --raw
		print -e $"✗ ($name) exit ($code) after (do $elapsed), log: ($log)"
	} else if $normal {
		print -e $"✓ ($name) \((open --raw $log | lines | length) lines, (do $elapsed), log: ($log)\)"
	}
	$code
}

def print-preamble [envs: record, cmd, args: list, trail: string] {
  let quoted_args = $args | each { |arg|
    if ($arg | into string | str contains ' ') { $arg | to nuon } else { $arg } }
  let env_pairs = if ($envs | is-empty) { [] } else { $envs | transpose name value }
  if ($env_pairs | is-not-empty) {
    $env_pairs | each { |row|
      let shown = if (is-secret-key $row.name) { "***redacted***" } else { $row.value }
      print -e (format-export $row.name $shown)
    }
  }
  print -e -n $"($cmd) ($quoted_args | str join ' ')($trail)"
}

# A progress or success line, which `quiet` drops; failures print at every level.
export def note [--stdout, msg: string] {
	if (verbosity) == "quiet" { return }
	if $stdout { print $msg } else { print -e $msg }
}

# Diagnostics go to stderr: callers capture stdout for the command's output alone.
export def --wrapped vrun [--trail="\n", --envs: record = {}, cmd, ...args] {
  if (verbosity) != "quiet" { print-preamble $envs $cmd $args $trail }
  with-env $envs {
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

# sayt.sh's MISE_VERSION, which sayt.zig pins alike.
def pinned-mise []: nothing -> string {
  open --raw ($path_self | path dirname | path join "sayt.sh") | parse -r 'MISE_VERSION="(?<v>[^"]+)"' | get 0.v
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
  # 2. The launchers' pinned mise, next to tools.nu or in their caches: sayt.zig
  # caches under ~/Library/Caches on macOS, sayt.sh under XDG's everywhere.
  let pinned = $"mise-(pinned-mise)"
  let xdg = $env.XDG_CACHE_HOME? | default ($env.HOME? | default "" | path join ".cache") | path join "sayt"
  let caches = if $is_windows {
    [($env.LOCALAPPDATA? | default "" | path join "sayt")]
  } else if ((uname | get kernel-name) == "Darwin") {
    [($env.HOME | path join "Library" "Caches" "sayt") $xdg]
  } else {
    [$xdg]
  }
  let candidates = [$base ...$caches] | each { |d| $d | path join $pinned $exe } | where { path exists }
  if ($candidates | is-not-empty) { return ($candidates | first) }
  # 3. Fall back to PATH
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
  mise-live (command-name mise $args) $envs $args
}

def mise-live [name: string, envs: record, args: list]: nothing -> int {
  with-env (mise-env) {
    hide-env -i MISE_LOCKED
    mise-trust $env.SAYT_MISE_BIN
    let unlocked = ($args.0? in ["tool-stub" "lock"])
    with-env (if $unlocked { {MISE_LOCKED: "0"} } else { {} }) {
      vrun-named $name $envs $env.SAYT_MISE_BIN $args
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

# Tool stubs isolate PATH; GoReleaser's hooks need the project's toolchain.
export def --wrapped run-goreleaser [...args] {
  let stub = stub-path "goreleaser"
  run-mise tool-stub $stub --version | ignore
  let version = (open --raw $stub | from toml | get version)
  let executable = (run-mise which goreleaser --tool $"http:($stub | path basename)@($version)" | str trim)
  let project = (run-mise env --json | from json)
  # Windows names it Path.
  let path_key = ($project | columns | where { |c| ($c | str lowercase) == "path" } | first)
  with-env ($project | update $path_key { split row (char esep) }) { vrun $executable ...$args }
}

# run-nu with run-live's contract, named by the caller: a `nu -c` script's
# words say nothing about what it is.
export def run-nu-named [name: string, args: list]: nothing -> int {
	mise-live $name {} ["tool-stub" (stub-path "nu") ...$args]
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
