# compose.nu — Docker Compose orchestration helpers
use tools.nu [vrun-live]
use dind.nu

# --session: an open dind bridge whose ABI (+ the HOST_ENV projection graphs
# env-source as the host.env secret) rides the compose env. The caller owns
# open/close, so one bridge can span several compose invocations.
# Returns the exit code run-live-style instead of raising, so callers can
# close the bridge and print a verdict on failure.
export def --wrapped compose-vrun [--session: any = null, cmd, ...args] {
	let base = { COMPOSE_BAKE: "true", BUILDX_NO_DEFAULT_ATTESTATIONS: "1" }
	let envs = if $session == null { $base } else {
		$base | merge $session.env | insert HOST_ENV (dind to-env-file $session.env)
	}
	vrun-live --envs $envs $cmd ...$args
}

export def --wrapped compose-vup [--session: any = null, target, ...args] {
	compose-vrun --session=$session docker compose up $target ...$args
}
