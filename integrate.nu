# integrate.nu — Integration testing workflow
use tools.nu [run-docker-compose]
use compose.nu [dind-vrun compose-vup]

export def --wrapped main [
	--target: string = "integrate" # Compose service to run
	--no-cache        # Build without Docker layer cache
	--progress: string = "auto" # Compose progress output (auto/plain/tty)
	--bake            # Use docker buildx bake instead of compose
	...args           # Additional flags passed to docker compose up or bake
] {
	if $bake {
		let passthrough = if ($args | length) > 0 and ($args | first) == "--" { $args | skip 1 } else { $args }
		let bake_args = ([
			"--progress", $progress
		] | if $no_cache { append "--no-cache" } else { $in }) ++ $passthrough ++ [ $target ]
		with-env { BUILDX_BAKE_ENTITLEMENTS_FS: "0" } {
			dind-vrun docker buildx bake ...$bake_args
		}
		if $env.LAST_EXIT_CODE != 0 { exit $env.LAST_EXIT_CODE }
		return
	}

	# Clean slate: remove any leftover containers from previous runs
	run-docker-compose down -v --timeout 0 --remove-orphans

	# If --no-cache, build without cache first
	if $no_cache {
		dind-vrun docker compose build --no-cache $target
	}

	# Run compose with dind environment and capture exit code
	compose-vup --progress $progress $target --abort-on-container-failure --exit-code-from $target --force-recreate --build --renew-anon-volumes --remove-orphans --attach-dependencies ...$args
	let exit_code = $env.LAST_EXIT_CODE

	# Only cleanup on success - on failure, keep containers for inspection
	if $exit_code == 0 {
		dind-vrun docker compose down -v --timeout 0 --remove-orphans
	} else {
		print -e "Integration failed. Containers left for inspection. Run 'docker compose logs' or 'docker compose down -v' when done."
		exit $exit_code
	}
}
