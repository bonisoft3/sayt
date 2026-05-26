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
	# ~/.docker/config.json (no credsStore reference), so the file
	# content drops straight into a bake sandbox's /root/.docker/
	# config.json.
	let home = ($env.HOME? | default "/root")
	let config_path = $"($home)/.docker/config.json"
	if ($config_path | path exists) {
		return (open --raw $config_path)
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

def "main kubeconfig" [] { kubeconfig }
export def kubeconfig [] {
	if (which kubectl | is-not-empty) {
	  kubectl config view --raw -o json
	} else {
		""
	}
}

def "main host-ip" [] { host-ip }
# Probes the host's IP as seen from a container on the host network.
# busybox is the smallest image with hostname; pin via lock's
# multi-platform sha. Pulled via the local docker daemon, which
# doesn't use buildkit's mirror config — so this contributes to
# the auth'd 200/6h docker.io pull budget. Keep the deps minimal.
export def host-ip [] {
	docker run --network=host busybox:musl@sha256:03db190ed4c1ceb1c55d179a0940e2d71d42130636a780272629735893292223 hostname -i | split row " " | last
}

def "main gateway-ip" [] { gateway-ip }
export def gateway-ip [] {
	docker run --add-host=gateway.docker.internal:host-gateway busybox:musl@sha256:03db190ed4c1ceb1c55d179a0940e2d71d42130636a780272629735893292223 sh -c 'cat /etc/hosts | grep "gateway.docker.internal$" | cut -f1 | head -n1'
}

def "main env-file" [--socat, --unset-otel] { env-file --socat=$socat --unset-otel=$unset_otel }
export def env-file [--socat, --unset-otel] {
	mut socat_container_id = ""
	mut testcontainers_host_override = ""
	mut docker_host = "unix:///var/run/docker.sock"

	let port = port 2375
	if ($socat) {
		let id = docker run -d -v //var/run/docker.sock:/var/run/docker.sock --network=host alpine/socat:1.8.0.0@sha256:a6be4c0262b339c53ddad723cdd178a1a13271e1137c65e27f90a08c16de02b8 -d0 $"TCP-LISTEN:($port),fork,backlog=1024,reuseaddr" UNIX-CONNECT:/var/run/docker.sock
		$docker_host = $"tcp://(host-ip):($port)"
		$testcontainers_host_override = (gateway-ip)
		$socat_container_id = $id
	}

	let docker_lines = [
		$"DOCKER_AUTH_CONFIG=\"(credentials | from json | to dotenvjson)\"",
		$"KUBECONFIG_DATA='(kubeconfig | str replace -am "\n" "" | str replace -am "127.0.0.1" (if ($testcontainers_host_override | is-empty) { "127.0.0.1" } else { $testcontainers_host_override }))'",
		$"DOCKER_HOST=($docker_host)",
		$"TESTCONTAINERS_HOST_OVERRIDE=($testcontainers_host_override)",
		$"SOCAT_CONTAINER_ID=($socat_container_id)"
	]
	let gha_lines = ([
		["ACTIONS_CACHE_URL" "ACTIONS_RUNTIME_TOKEN"]
	] | flatten
		| where { |name| $name in $env }
		| each { |name| $"($name)=($env | get $name)" })
  # Prevent clash with depot: https://github.com/docker/setup-buildx-action/issues/356
	let otel_lines = [
		"OTEL_EXPORTER_OTLP_TRACES_PROTOCOL=",
		"OTEL_TRACE_PARENT=",
		"OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=",
		"OTEL_TRACES_EXPORTER="
	]
	let lines = if $unset_otel {
		$docker_lines | append $otel_lines | append $gha_lines
	} else {
		$docker_lines | append $gha_lines
	}

	($lines | str join "\n") + "\n"
}

def "to dotenvjson" []: any -> string {
    $in | to json -r | str replace -a '"' '\"'
}


def main [] { }
