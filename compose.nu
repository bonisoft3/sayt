# compose.nu — Docker Compose orchestration helpers
use tools.nu [run-docker vrun]
use dind.nu

export def --wrapped dind-vrun [cmd, ...args] {
	let _t_start = (date now)
	let host_env_from_secret = ("/run/secrets/host.env" | path exists)
	let host_env = if $host_env_from_secret {
		open --raw /run/secrets/host.env
	} else {
		dind env-file --socat
	}
	let _t_hostenv = (date now)
	print -e $"BAYT_TIMING host.env: (($_t_hostenv - $_t_start) / 1ms)ms"
	let socat_container_id = ($host_env
		| lines
		| where $it =~ "SOCAT_CONTAINER_ID"
		| split column "="
		| get ($in | columns | last)
		| first
		| default "")
	# Write to a temp file so Docker Compose can use file: secrets for
	# both build-time (BuildKit) and runtime container mounts.
	# BAYT_HOST_ENV_FILE is referenced in generated compose files.
	# COMPOSE_BAKE=true → compose builds via `buildx bake`: parallel
	# cross-service builds + better cache sharing.
	let tmp_env_file = (^mktemp)
	$host_env | save --force $tmp_env_file
	vrun --envs {
		"HOST_ENV": $host_env,
		"BAYT_HOST_ENV_FILE": $tmp_env_file,
		"COMPOSE_BAKE": "true",
		# Skip SBOM + provenance attestation generation. Saves an extra
		# manifest export per stage; we don't consume these locally and
		# the integrate path produces no published artifact.
		"BUILDX_NO_DEFAULT_ATTESTATIONS": "1",
	} $cmd ...$args
	let exit_code = $env.LAST_EXIT_CODE
	let _t_compose = (date now)
	print -e $"BAYT_TIMING compose-up: (($_t_compose - $_t_hostenv) / 1ms)ms"
	rm -f $tmp_env_file
	if (not $host_env_from_secret) and ($socat_container_id | is-not-empty) {
		run-docker rm -f $socat_container_id
	}
	let _t_cleanup = (date now)
	print -e $"BAYT_TIMING dind-cleanup: (($_t_cleanup - $_t_compose) / 1ms)ms"
	print -e $"BAYT_TIMING dind-vrun TOTAL: (($_t_cleanup - $_t_start) / 1ms)ms"
	if $exit_code != 0 {
		exit $exit_code
	}
}

export def --wrapped compose-vup [target, ...args] {
	dind-vrun docker compose up $target ...$args
}
