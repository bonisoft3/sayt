# launch.nu — Launch environment.
#
# Usage:
#   sayt launch            bring up launch + deps and detach. Returns 0
#                          when ready: healthcheck passes (server mode)
#                          or container exits 0 (CLI mode). Tear down
#                          with `docker compose down -v`.
#   sayt launch --watch    foreground + file sync for HMR (dev loop).
#
# Both modes go through `compose up`. --wait conflicts with --attach-
# dependencies / --abort-on-container-failure / --exit-code-from, so
# they're never combined.
use compose.nu [compose-vup]
use tools.nu [run-docker-compose]

export def --wrapped main [
	--watch    # foreground + file sync for HMR (dev loop)
	...args
] {
	# Hard down before up: --force-recreate alone leaves anonymous
	# volumes and orphaned services in place.
	run-docker-compose down -v --timeout 0 --remove-orphans

	if $watch {
		compose-vup launch --build --force-recreate --remove-orphans --attach-dependencies --watch ...$args
	} else {
		# --wait detaches and returns when ready: 0 once healthy for
		# services with healthcheck; container exit code for CLI runs.
		compose-vup launch --build --force-recreate --remove-orphans --wait ...$args
	}
}
