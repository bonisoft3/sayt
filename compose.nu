# compose.nu — Docker Compose orchestration helpers
use tools.nu [run-docker run-docker-compose vrun]
use dind.nu

export def --wrapped dind-vrun [cmd, ...args] {
	let host_env_from_secret = ("/run/secrets/host.env" | path exists)
	let host_env = if $host_env_from_secret {
		open --raw /run/secrets/host.env
	} else {
		dind env-file --socat
	}
	let socat_container_id = ($host_env
		| lines
		| where $it =~ "SOCAT_CONTAINER_ID"
		| split column "="
		| get ($in | columns | last)
		| first
		| default "")
	# COMPOSE_BAKE=true → compose builds via `buildx bake`: parallel
	# cross-service builds + better cache sharing.
	vrun --envs { "HOST_ENV": $host_env, "COMPOSE_BAKE": "true" } $cmd ...$args
	let exit_code = $env.LAST_EXIT_CODE
	if (not $host_env_from_secret) and ($socat_container_id | is-not-empty) {
		run-docker rm -f $socat_container_id
	}
	if $exit_code != 0 {
		exit $exit_code
	}
}

export def --wrapped compose-vup [--progress=auto, target, ...args] {
	dind-vrun docker compose up $target ...$args
}

export def --wrapped compose-vrun [--progress=auto, target, ...args] {
	run-docker-compose down -v --timeout 0 --remove-orphans $target
	# Recreate containers whose compose config changed (images, env, commands)
	# without starting them. Prevents stale dependencies from surviving across
	# launches when pipeline YAMLs, Dockerfiles, or env vars change.
	run-docker-compose up --build --no-start
	dind-vrun docker compose --progress=($progress) run --build --service-ports $target ...$args
}
