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

	# Check if helper exists in PATH
	if (which $helper | is-empty) {
		# TODO(davi) return from docker config file instead
		return "{}"
	}

	# Get credentials list and parse as JSON
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

	# Create the final config and encode
	{auths: $registries}
	| to json
}

export def pinned-images [dockerfile: path] {
    open $dockerfile
    | lines
    | where { |line| $line =~ '^FROM ' and $line =~ '@sha256:' }
    | each { |line|
        $line | str replace --regex '^FROM ([^ ]+).*$' '$1'
    }
}

def "main kubeconfig" [] { kubeconfig }
export def kubeconfig [] {
	if (which kubectl | is-not-empty) {
	  kubectl config view --raw -o json
	}
}

def "main host-ip" [] { host-ip }
export def host-ip [] {
	docker run --network=host cgr.dev/chainguard/wolfi-base:latest@sha256:deba562a90aa3278104455cf1c34ffa6c6edc6bea20d6b6d731a350e99ddd32a hostname -i | split row " " | last
}

def "main gateway-ip" [] { gateway-ip }
export def gateway-ip [] {
	docker run --add-host=gateway.docker.internal:host-gateway cgr.dev/chainguard/wolfi-base:latest@sha256:deba562a90aa3278104455cf1c34ffa6c6edc6bea20d6b6d731a350e99ddd32a sh -c 'cat /etc/hosts | grep "gateway.docker.internal$" | cut -f1 | head -n1'
}

def "main env-file" [--socat, --unset-otel] { env-file --socat=$socat --unset-otel=$unset_otel }
export def env-file [--socat, --unset-otel] {
	mut socat_container_id = ""
	mut testcontainers_host_override = ""
	mut docker_host = "unix:///var/run/docker.sock"
	let port = port 2375
	if ($socat) {
		let id = docker run -d -v //var/run/docker.sock:/var/run/docker.sock --network=host alpine/socat:1.8.0.0@sha256:a6be4c0262b339c53ddad723cdd178a1a13271e1137c65e27f90a08c16de02b8 -d0 $"TCP-LISTEN:($port),fork" UNIX-CONNECT:/var/run/docker.sock
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
  # Prevent clash with depot: https://github.com/docker/setup-buildx-action/issues/356
	let otel_lines = [
		"OTEL_EXPORTER_OTLP_TRACES_PROTOCOL=",
		"OTEL_TRACE_PARENT=",
		"OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=",
		"OTEL_TRACES_EXPORTER="
	]
	let lines = if $unset_otel { $docker_lines | append $otel_lines } else { $docker_lines }

	($lines | str join "\n") + "\n"
}

def "to dotenvjson" []: any -> string {
    $in | to json -r | str replace -a '"' '\"'
}


def main [] { }
