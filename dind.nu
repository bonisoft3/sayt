#!/usr/bin/env nu

def get-credential-helper [] {
    let os = (sys host | get name)
    match $os {
        'Darwin' => { "docker-credential-osxkeychain" }
        'Windows' => { "docker-credential-wincred" }
        'Linux' => { "docker-credential-secretservice" }
        _ => { error make {msg: $"Unsupported operating system: ($os)"} }
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
		error make {msg: $"Docker credential helper '($helper)' not found. Please install it first."}
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
    | filter { |line| $line =~ '^FROM ' and $line =~ '@sha256:' }
    | each { |line|
        $line | str replace --regex '^FROM ([^ ]+).*$' '$1'
    }
}

def "main kubeconfig" [] { kubeconfig }
export def kubeconfig [] {
	if (which kubectl | is-not-empty) {
	  kubectl config view
	}
}

def "main host-ip" [] { host-ip }
export def host-ip [] {
	docker run --network=host cgr.dev/chainguard/wolfi-base:latest@sha256:378e1d3d5ced3c8ea83c92784b081972bb235c813db8b56f936c50deac8357f3 hostname -i
}

def "main gateway-ip" [] { gateway-ip }
export def gateway-ip [] {
	docker run --add-host=gateway.docker.internal:host-gateway cgr.dev/chainguard/wolfi-base:latest@sha256:378e1d3d5ced3c8ea83c92784b081972bb235c813db8b56f936c50deac8357f3 sh -c 'cat /etc/hosts | grep "gateway.docker.internal$" | cut -f1'
}

def "main env-file" [--socat] { env-file --socat=$socat }
export def env-file [--socat] {
	mut socat_container_id = ""
	mut testcontainers_host_override = ""
	mut docker_host = "unix:///var/run/docker.sock"
	let port = port 2375
	if ($socat) {
		let id = docker run -d -v //var/run/docker.sock:/var/run/docker.sock --network=host alpine/socat:1.8.0.0@sha256:a6be4c0262b339c53ddad723cdd178a1a13271e1137c65e27f90a08c16de02b8 -d0 $"TCP-LISTEN:($port),fork" UNIX-CONNECT:/var/run/docker.sock
		$docker_host = $"tcp://(host-ip):($port)"
		$testcontainers_host_override = gateway-ip
		$socat_container_id = $id
	}

	let lines = [
		$"DOCKER_AUTH_CONFIG='(credentials | str replace -am "\n" "")'",
		$"KUBECONFIG='(kubeconfig | from yaml | to json | str replace -am "\n" "")'",
		$"DOCKER_HOST=($docker_host)",
		$"TESTCONTAINERS_HOST_OVERRIDE=($testcontainers_host_override)"
		$"SOCAT_CONTAINER_ID=($socat_container_id)"
	]
	$lines | str join "\n"
}


def main [] { }
