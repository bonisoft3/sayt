# compose.nu — Docker Compose orchestration helpers
use tools.nu [vrun]
use dind.nu

# --host-env serves graphs whose host.env secret env-sources HOST_ENV.
export def --wrapped compose-vrun [--host-env, cmd, ...args] {
	let base = { COMPOSE_BAKE: "true", BUILDX_NO_DEFAULT_ATTESTATIONS: "1" }
	if not $host_env {
		vrun --envs $base $cmd ...$args
		if $env.LAST_EXIT_CODE != 0 { exit $env.LAST_EXIT_CODE }
		return
	}
	let session = (dind bridge open --socat --auth --kube)
	vrun --envs ($base | merge $session.env | insert HOST_ENV (dind to-env-file $session.env)) $cmd ...$args
	let exit_code = $env.LAST_EXIT_CODE
	dind bridge close $session
	if $exit_code != 0 { exit $exit_code }
}

export def --wrapped compose-vup [--host-env, target, ...args] {
	compose-vrun --host-env=$host_env docker compose up $target ...$args
}
