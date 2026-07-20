#!/usr/bin/env nu

def get-credential-helper [] {
    let os = (uname | get kernel-name)
    # Check if running in WSL
    let is_wsl = (uname | get kernel-release | str contains "WSL")
    if $is_wsl {
        # We're on WSL, use the Windows credential helper
        "docker-credential-wincred.exe"
    } else {
        # Not on WSL, use the appropriate helper for the OS
        match $os {
            'Darwin' => { "docker-credential-osxkeychain" }
            'Windows_NT' => { "docker-credential-wincred.exe" }
            'Linux' => { "docker-credential-secretservice" }
            _ => { error make {msg: $"Unsupported operating system: ($os)"} }
        }
    }
}

def "main credentials" [] { credentials }
export def credentials [] {
	if ("DOCKER_AUTH_CONFIG" in $env) { return $env.DOCKER_AUTH_CONFIG }
	if ("SECRETS_ENV" in $env) {
		let $docker_auth_config = $env.SECRETS_ENV|rg DOCKER_AUTH_CONFIG| from toml |get "DOCKER_AUTH_CONFIG"
		return $docker_auth_config
	}

	let helper = (get-credential-helper)

	# Helper path (Mac/Windows + Linux dev with secretservice): build a
	# config from the keychain. When the helper binary is missing
	# (typical on GHA Linux runners), fall through to reading
	# config.json directly.
	if (which $helper | is-not-empty) {
		let registries = (do { ^$helper list } | complete
			| if $in.exit_code != 0 {
				error make {msg: $"Failed to list credentials: ($in.stderr)"}
			} else {
				$in.stdout
			}
			| from json
			| transpose key value                  # Convert record to table
			| where key !~ 'token'                # Filter out token entries
			| each {|row|
				let creds = ($row.key | ^$helper get | from json)
				{
					$row.key: {
						auth: ($"($creds.Username):($creds.Secret)" | encode base64)
					}
				}
			}
			| reduce --fold {} {|it, acc| $acc | merge $it})

		return ({auths: $registries} | to json)
	}

	# CI fallback: docker/login-action writes inline base64 auths to
	# ~/.docker/config.json (no credsStore reference). Forward only the
	# auths map: strict DOCKER_AUTH_CONFIG parsers (testcontainers-go
	# dockercfg) reject the extra top-level fields runner CLIs and
	# `depot configure-docker` add (e.g. "aliases"), dropping all
	# registry auth. Sanitizing config.json downstream doesn't stick —
	# the depot action chain rewrites it after consumer-side steps.
	let home = ($env.HOME? | default "/root")
	let config_path = $"($home)/.docker/config.json"
	if ($config_path | path exists) {
		return ({auths: (open $config_path | get --optional auths | default {})} | to json --raw)
	}

	"{}"
}

export def pinned-images [dockerfile: path] {
    open $dockerfile
    | lines
    | where { |line| $line =~ '^FROM ' and $line =~ '@sha256:' }
    | each { |line|
        $line | str replace --regex '^FROM ([^ ]+).*$' '$1'
    }
}

def "main buildx-instance" [builder?: string] { buildx-instance $builder }
# Returns the verbatim content of `~/.docker/buildx/instances/<builder>`
# on the host. Used to ferry the host's docker-container builder into
# bake sandboxes (RUN containers, inner-bake CLIs) so the inner bake
# uses a driver that supports cache-to=type=registry,mode=max — the
# default `docker` driver inside a sandbox can't push registry cache.
#
# Empty string when no builder name is given or the file doesn't
# exist (local dev without a named builder, or first invocation
# before setup-buildx-action runs in CI).
export def buildx-instance [builder?: string] {
	if ($builder | is-empty) { return "" }
	let home = ($env.HOME? | default "/root")
	let path = $"($home)/.docker/buildx/instances/($builder)"
	if ($path | path exists) { open --raw $path } else { "" }
}

def "main buildx-instance-rewritten" [builder?: string, --docker-host: string = ""] { buildx-instance-rewritten $builder --docker-host=$docker_host }
# Returns the host's buildx instance file with every `"Endpoint":"..."`
# rewritten to point at `--docker-host`. Lets the host pre-bake a
# ready-to-place blob: the sandbox just writes it to
# /root/.docker/buildx/instances/<builder> via env-sourced secret, no
# sandbox-side sed. Empty `--docker-host` returns the raw content;
# missing instance file returns empty string. Docker Desktop stores
# named endpoints like `desktop-linux` and Linux CI usually stores
# `unix:///var/run/docker.sock`; neither is reachable from inside a
# bake RUN sandbox, so this rewrite is what makes the inner bake see
# the same builder identity as the host.
export def buildx-instance-rewritten [builder?: string, --docker-host: string = ""] {
	let raw = (buildx-instance $builder)
	if ($raw | is-empty) { return "" }
	if ($docker_host | is-empty) { return $raw }
	$raw | str replace -ar '"Endpoint":"[^"]*"' $"\"Endpoint\":\"($docker_host)\""
}

def "main kubeconfig" [] { kubeconfig }
export def kubeconfig [] {
	if (which kubectl | is-not-empty) {
	  kubectl config view --raw -o json
	} else {
		""
	}
}

def "main host-ip" [] { host-ip }
def "main parse-host-ip" [raw: string] { parse-host-ip $raw }

# Parse `hostname -i` output → the first IP. Multi-homed hosts print several
# space-separated addrs with a TRAILING SPACE (that empty trailing token regressed the old
# `split " " | last`); take the first non-empty field, matching the integrate action twin's
# `awk '{print $1}'`. Pure + total ("" when none) — exercised by dind_test.nu.
export def parse-host-ip [raw: string]: nothing -> string {
	let fields = ($raw | split row " " | each {|s| $s | str trim} | where {|s| $s | is-not-empty})
	if ($fields | is-empty) { "" } else { $fields | first }
}

# Host IP (as seen from a host-network container) for the socat bridge. busybox via
# mirror.gcr.io — a LOCAL `docker run` bypasses buildkit's docker.io→mirror.gcr.io config, so
# a bare ref hits the pull-rate cap. Fail loud on empty: a silent "" → docker_host=tcp://:2375.
export def host-ip [] {
	let probe = (docker run --network=host mirror.gcr.io/library/busybox:musl@sha256:03db190ed4c1ceb1c55d179a0940e2d71d42130636a780272629735893292223 hostname -i | complete)
	if $probe.exit_code != 0 {
		error make {msg: $"host-ip: docker run failed \(exit ($probe.exit_code)\) — often docker.io pull rate limit. stderr: ($probe.stderr | str trim)"}
	}
	let ip = (parse-host-ip $probe.stdout)
	if ($ip | is-empty) {
		error make {msg: $"host-ip: no address from 'hostname -i': ($probe.stdout | to nuon)"}
	}
	$ip
}

def "main gateway-ip" [] { gateway-ip }
# The probe container reads the --add-host mapping docker itself resolved —
# the in-container view of the host gateway. --rm so repeated bridge opens
# don't accumulate exited containers. When the probe can't run (host that
# never pulled the probe image, offline), fall back to the bridge network's
# IPAM gateway — the same address on stock topologies.
export def gateway-ip [] {
	let probe = (do { docker run --rm --add-host=gateway.docker.internal:host-gateway mirror.gcr.io/library/busybox:musl@sha256:03db190ed4c1ceb1c55d179a0940e2d71d42130636a780272629735893292223 sh -c 'grep "gateway.docker.internal$" /etc/hosts | cut -f1 | head -n1' } | complete)
	if $probe.exit_code == 0 and ($probe.stdout | str trim | is-not-empty) {
		$probe.stdout
	} else {
		docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}'
	}
}

# Frontend dimension of the cache scope: df<digest12> (df<tag> for
# digestless refs) when $BUILDKIT_SYNTAX pins an external
# dockerfile frontend, `builtin` otherwise. The frontend generates the
# LLB that chain IDs hash, so pinned and built-in caches must not
# share a namespace.
def frontend-dim []: nothing -> string {
	let syntax = ($env.BUILDKIT_SYNTAX? | default "")
	if ($syntax | is-empty) { return "builtin" }
	let m = ($syntax | parse -r '@sha256:(?P<d>[0-9a-f]{12})')
	if ($m | is-not-empty) {
		$"df($m.0.d)"
	} else {
		let tag = ($syntax | split row "@" | first | split row ":" | last)
		$"df($tag | str replace -ar '[^a-zA-Z0-9._-]' '-')"
	}
}

# Sanitize a branch name to the OCI tag charset and bound its length so
# composed cache tags stay under the 128-char limit: strip refs/heads/,
# fold anything outside [a-zA-Z0-9._-] to '-'. Branches ≤24 chars pass
# through verbatim (so `main` and short names stay readable and a branch's
# scope still equals its main fallback); longer names collapse to a
# 16-char slug + 8 hex of the full name's sha256 — bounded (≤25) and
# collision-safe.
def sanitize-branch [branch: string]: nothing -> string {
	let b = ($branch
		| str replace -r '^refs/heads/' ''
		| str replace -ar '[^a-zA-Z0-9._-]' '-')
	if ($b | is-empty) { return "main" }
	if (($b | str length) <= 24) { return $b }
	$"($b | str substring 0..15)-($b | hash sha256 | str substring 0..7)"
}

def "main buildx-fingerprint" [builder?: string] { buildx-fingerprint $builder }
# "bk<version>-<frontend>-<os>-<arch>" identity of a LOCAL buildx
# builder — every dimension feeds chain-ID computation. Pure nushell:
# dind.nu also runs on native Windows, so no POSIX sh on the host
# path. Probing via `buildx inspect` is sound only for builders the
# repo controls (CI pins the buildkit image digest); depot's fleet
# versions drift mid-rollout, so depot flows get a declared scope from
# the sayt/depot action instead — never probe a remote fleet.
export def buildx-fingerprint [builder?: string] {
	let args = if ($builder | is-empty) { [] } else { [$builder] }
	let info = (^docker buildx inspect --bootstrap ...$args | lines)
	let bk_version = ($info
		| where { |l| $l =~ "(?i)buildkit" and $l =~ "v?[0-9]+\\.[0-9]+" }
		| get 0?
		| default ""
		| parse -r "v?(?P<v>[0-9]+\\.[0-9]+\\.[0-9]+)"
		| get v?
		| first
		| default "unknown")
	let platform = ($info
		| where { |l| $l =~ "Platforms:" }
		| get 0?
		| default ""
		| parse -r "(?P<p>linux/[a-z0-9]+)"
		| get p?
		| first
		| default "linux/amd64"
		| str replace "/" "-")
	$"bk($bk_version)-(frontend-dim)-($platform)"
}

# The HOST_ENV projection: `set -a; . file` text for graphs that env-source it
# as a secret. JSON members are compacted so sourcing survives; single-quote
# wrapping keeps shell metacharacters literal (JSON carries no single quotes).
export def to-env-file [rec: record]: nothing -> string {
	let json_keys = ["DOCKER_AUTH_CONFIG" "KUBECONFIG_DATA" "BUILDX_INSTANCE"]
	let lines = ($rec
		| transpose key value
		| where { |r| $r.value | is-not-empty }
		| each { |r|
			let v = if ($r.key in $json_keys) { $r.value | from json | to json -r } else { $r.value }
			$"($r.key)='($v)'"
		})
	($lines | str join "\n") + "\n"
}

# Open a dind bridge, collecting only the explicitly requested facilities — one
# boolean flag per capability, no inference (dind is the mechanism layer; policy
# lives in the caller). The one implication is `builder ⇒ socat`: the
# transported buildx instance is rewritten to the socat tcp endpoint, so a
# builder without the bridge is dead. `env` is always the complete sandbox ABI,
# unrequested facilities empty, so Bayt's secret + RUN shape stay cache-stable
# across capability sets. Pair with `bridge close`.
export def "bridge open" [
	--auth                  # host registry creds          → DOCKER_AUTH_CONFIG
	--builder: string = ""  # host buildx builder name      → BUILDX_*/CACHE_SCOPE* (implies --socat)
	--socat                 # bridge host docker sock → tcp  → DOCKER_HOST_TCP
	--kube                  # host kubeconfig               → KUBECONFIG_DATA
	--testcontainers        # testcontainers host override   → TESTCONTAINERS_HOST_OVERRIDE
	--gha                   # forward GHA cache env          → ACTIONS_*
	--frontend              # forward dockerfile frontend    → BUILDKIT_SYNTAX
	--depot                 # forward depot creds (+ DEPOT_DISABLE_OTEL) → DEPOT_*
]: nothing -> record {
	let socat_on = ($socat or ($builder | is-not-empty))
	let bridge = if $socat_on {
		let port = (port 2375)
		let id = (docker run -d -v //var/run/docker.sock:/var/run/docker.sock --network=host mirror.gcr.io/alpine/socat:1.8.0.0@sha256:a6be4c0262b339c53ddad723cdd178a1a13271e1137c65e27f90a08c16de02b8 -d0 $"TCP-LISTEN:($port),fork,backlog=1024,reuseaddr" UNIX-CONNECT:/var/run/docker.sock)
		{id: $id, docker_host: $"tcp://(host-ip):($port)"}
	} else {
		{id: "", docker_host: "unix:///var/run/docker.sock"}
	}
	# Caller wins; else the docker gateway — the one address that routes to
	# published ports from every sandbox topology (host-netns builders, where
	# the bridge host may not loop back, and bridged builders, where loopback
	# is wrong). Mirrors the runtime services' extra_hosts: host-gateway.
	let tc_host = if $testcontainers {
		let caller = ($env.TESTCONTAINERS_HOST_OVERRIDE? | default "")
		if ($caller | is-not-empty) { $caller } else { gateway-ip | str trim }
	} else { "" }
	# kind's kubeconfig points the API server at 127.0.0.1; from inside the
	# sandbox that must resolve to the testcontainers host when one is set.
	let kube_data = if $kube { kubeconfig } else { "" }
	let kube_data = if ($tc_host | is-not-empty) { $kube_data | str replace -a "127.0.0.1" $tc_host } else { $kube_data }
	let bx = if ($builder | is-not-empty) {
		let fingerprint = (buildx-fingerprint $builder)
		let branch = (sanitize-branch ($env.BRANCH? | default "main"))
		{
			builder: $builder
			instance: (buildx-instance-rewritten $builder --docker-host $bridge.docker_host)
			scope: $"($branch)-($fingerprint)"
			fallback: $"main-($fingerprint)"
		}
	} else {
		{builder: "", instance: "", scope: "", fallback: ""}
	}
	{
		env: {
			DOCKER_HOST_TCP: (if $socat_on { $bridge.docker_host } else { "" })
			DOCKER_AUTH_CONFIG: (if $auth { credentials } else { "" })
			BUILDX_BUILDER: $bx.builder
			BUILDX_INSTANCE: $bx.instance
			CACHE_SCOPE: $bx.scope
			CACHE_SCOPE_FALLBACK: $bx.fallback
			KUBECONFIG_DATA: $kube_data
			TESTCONTAINERS_HOST_OVERRIDE: $tc_host
			ACTIONS_CACHE_URL: (if $gha { $env.ACTIONS_CACHE_URL? | default "" } else { "" })
			ACTIONS_RUNTIME_TOKEN: (if $gha { $env.ACTIONS_RUNTIME_TOKEN? | default "" } else { "" })
			DEPOT_TOKEN: (if $depot { $env.DEPOT_TOKEN? | default "" } else { "" })
			DEPOT_PROJECT_ID: (if $depot { $env.DEPOT_PROJECT_ID? | default "" } else { "" })
			# DEPOT_DISABLE_OTEL is depot's own switch for the buildx/depot OTEL
			# clash (docker/setup-buildx-action#356) — no OTEL_* unsetting by hand.
			DEPOT_DISABLE_OTEL: (if $depot { "1" } else { "" })
			BUILDKIT_SYNTAX: (if $frontend { $env.BUILDKIT_SYNTAX? | default "" } else { "" })
		}
		socat_container_id: $bridge.id
	}
}

# Close a bridge opened by `bridge open`. The ownership token stays out of the
# sandbox environment, so callers never need to parse a dotenv payload.
# Null-tolerant: plain compose-mode integrate opens no bridge and passes null.
export def "bridge close" [session: any = null] {
	if $session == null { return }
	let id = ($session.socat_container_id? | default "")
	if ($id | is-not-empty) {
		do { docker rm -f $id } | complete | ignore
	}
}

def "main env-file" [--socat, --builder: string = ""] { env-file --socat=$socat --builder=$builder }
# Legacy env-file blob for `set -a; . file` consumers. Thin wrapper over `bridge
# open --host-env`: it leaves the socat bridge open (the caller tears it down via
# the trailing SOCAT_CONTAINER_ID). gha/frontend auto-forward from host env.
export def env-file [--socat, --builder: string = ""] {
	let want_gha = (("ACTIONS_CACHE_URL" in $env) and ("ACTIONS_RUNTIME_TOKEN" in $env))
	let want_frontend = ($env.BUILDKIT_SYNTAX? | default "" | is-not-empty)
	let session = (bridge open --socat=$socat --auth --kube --builder=$builder --gha=$want_gha --frontend=$want_frontend)
	let socat_line = if ($session.socat_container_id | is-empty) { "" } else { $"SOCAT_CONTAINER_ID='($session.socat_container_id)'\n" }
	(to-env-file $session.env) + $socat_line
}

def main [] { }
