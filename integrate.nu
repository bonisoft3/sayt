# integrate.nu — Integration testing workflow.
#
# Two paths:
#   * default — `docker compose up <target>` against the per-project
#     compose graph. Builds + loads every stage as a docker image, runs
#     the requested service. For projects whose integrate stage relies
#     on compose-runtime semantics (entrypoint, network, volumes,
#     testcontainers shadows, etc.).
#   * --bake — `docker buildx bake` against a `docker compose
#     config`-flattened compose file, with --builder selectable so
#     callers can pick any buildx builder. The integration test
#     executes inside the bake target's RUN, so bake's exit code IS
#     the test verdict. Output is `type=cacheonly`: no image
#     materialization, no compose-up. Opt-in per project via
#     `say.integrate.args: "--bake"` in .say.yaml.

use tools.nu [run-docker run-docker-compose]
use compose.nu [dind-vrun compose-vup]
use dind.nu

export def --wrapped main [
	--target: string = "integrate" # Compose service / bake target
	--no-cache        # Build without cache
	--progress: string = "auto" # Progress output (auto/plain/tty)
	--bake            # Use docker buildx bake instead of compose
	--builder: string # buildx builder for --bake (e.g. "container", "depot")
	...args           # Additional flags passed to compose up or bake
] {
	if $bake {
		# Flatten the compose graph via `docker compose config` before
		# bake. compose's include resolution dedupes services that
		# appear in multiple included files (e.g. shared bayt-runtime-
		# stub); bake otherwise errors with "services.X conflicts with
		# imported resource".
		let _t_start = (date now)
		let host_env = (dind env-file --socat)
		let socat_id = ($host_env | lines | where $it =~ "SOCAT_CONTAINER_ID" | first | default "" | split row "=" | last)
		# Four env vars feed bayt's env-sourced compose secrets, which
		# the inject step in each consuming target materializes as files
		# (or env exports) inside the inner sandbox:
		#   DOCKER_HOST        → /run/secrets/docker_host
		#                        (socat-bridged daemon endpoint)
		#   DOCKER_AUTH_CONFIG → /run/secrets/docker_config
		#                        (host ~/.docker/config.json; buildkit
		#                        reads registry auth client-side, so
		#                        without this depot cache-from 401s
		#                        and Docker Hub pulls go anonymous)
		#   BUILDX_INSTANCE    → /run/secrets/buildx_instance
		#   BUILDX_BUILDER     → /run/secrets/buildx_builder
		#                        (host's docker-container builder file
		#                        + name; the sandbox's default `docker`
		#                        driver can't export cache-to=registry,
		#                        mode=max, so without this the inner
		#                        bake's cache-to silently fails)
		let docker_host_val = ($host_env | lines | where $it =~ "^DOCKER_HOST_TCP=" | first | default "DOCKER_HOST_TCP=" | split row "=" | skip 1 | str join "=")
		let testcontainers_host_val = ($host_env | lines | where $it =~ "^TESTCONTAINERS_HOST_OVERRIDE=" | first | default "TESTCONTAINERS_HOST_OVERRIDE=" | split row "=" | skip 1 | str join "=")
		let docker_config_val = (dind credentials)
		let buildx_instance_val = (dind buildx-instance $builder)
		let buildx_builder_val = if ($builder | is-empty) { "" } else { $builder }
		let _t_hostenv = (date now)
		print -e $"BAYT_TIMING bake host.env: (($_t_hostenv - $_t_start) / 1ms)ms"

		# `--allow=fs.read=<worktree-root>` (passed into bake below)
		# silences bake's filesystem-entitlement warning when contexts
		# in the flat compose resolve outside the bake file's dir.
		# `git rev-parse --show-toplevel` returns the worktree root —
		# load-bearing for git worktrees, where main repo's root is a
		# sibling of the current worktree's root.
		let worktree_root = (^git rev-parse --show-toplevel | str trim)

		# DOCKER_HOST_TCP (not DOCKER_HOST) carries the socat-bridged daemon
		# endpoint into compose's secret env-source. Setting DOCKER_HOST
		# here would point the outer bake CLI at a tcp endpoint that's
		# only reachable inside Docker Desktop's VM (i/o timeout from the
		# macOS host). The sandbox's inject body extracts DOCKER_HOST_TCP
		# back into $DOCKER_HOST via var.contents, so inner tooling sees
		# the value where it expects it.
		let bake_exit = with-env {
			DOCKER_HOST_TCP: $docker_host_val,
			TESTCONTAINERS_HOST_OVERRIDE: $testcontainers_host_val,
			DOCKER_AUTH_CONFIG: $docker_config_val,
			BUILDX_INSTANCE: $buildx_instance_val,
			BUILDX_BUILDER: $buildx_builder_val,
			BUILDX_NO_DEFAULT_ATTESTATIONS: "1",
			# Pins image-manifest timestamps to the unix epoch. Without
			# this, buildkit stamps wall-clock time and identical-source
			# reruns produce different digests — drifting any downstream
			# step that hashes those digests into its cache key.
			SOURCE_DATE_EPOCH: "0",
			# Disables bake's filesystem-entitlement block when contexts
			# resolve outside the bake file's dir (the flat compose
			# lives in /tmp, contexts point at the worktree). The
			# --allow=fs.read flag below silences the accompanying
			# warning; this env var clears the hard block.
			BUILDX_BAKE_ENTITLEMENTS_FS: "0",
		} {
			let tmpdir = (^mktemp -d | str trim)
			let flat_compose = $"($tmpdir)/compose.yaml"
			^docker compose config -o $flat_compose

			let passthrough = if ($args | length) > 0 and ($args | first) == "--" { $args | skip 1 } else { $args }
			let builder_args = if ($builder | is-empty) { [] } else { ["--builder", $builder] }
			let bake_args = ($builder_args ++ [
				$"--allow=fs.read=($worktree_root)",
				"-f", $flat_compose,
				"--set", "*.output=type=cacheonly",
				"--progress", $progress
			] | if $no_cache { append "--no-cache" } else { $in }) ++ $passthrough ++ [ $target ]
			^docker buildx bake ...$bake_args
			let ec = $env.LAST_EXIT_CODE
			rm -rf $tmpdir
			$ec
		}
		let _t_bake = (date now)
		print -e $"BAYT_TIMING bake build: (($_t_bake - $_t_hostenv) / 1ms)ms"

		if ($socat_id | is-not-empty) { run-docker rm -f $socat_id | ignore }
		let _t_cleanup = (date now)
		print -e $"BAYT_TIMING bake cleanup: (($_t_cleanup - $_t_bake) / 1ms)ms"
		print -e $"BAYT_TIMING bake TOTAL: (($_t_cleanup - $_t_start) / 1ms)ms"

		if $bake_exit != 0 {
			print -e $"(ansi red_bold)integrate ✗ failed(ansi reset)"
			exit $bake_exit
		}
		print $"(ansi green_bold)integrate ✓ passed(ansi reset)"
		return
	}

	# Clean slate: remove any leftover containers from previous runs.
	run-docker-compose down -v --timeout 0 --remove-orphans

	# Disable buildkit's default provenance + SBOM attestations: they
	# embed wall-clock timestamps in image manifests, drifting digests
	# across runs. For chained bayt targets (one FROMs another), that
	# drift cascades into cache misses on downstream RUNs.
	let exit_code = with-env {BUILDX_NO_DEFAULT_ATTESTATIONS: "1"} {
		if $no_cache {
			dind-vrun docker compose build --no-cache $target
		}
		# `compose up` has no --progress flag (only `compose build`
		# does); when --no-cache is set, the build above already
		# honored $progress.
		compose-vup $target --abort-on-container-failure --exit-code-from $target --force-recreate --build --renew-anon-volumes --remove-orphans --attach-dependencies ...$args
		$env.LAST_EXIT_CODE
	}

	# Explicit pass/fail verdict. `compose up --exit-code-from` always
	# emits a red "Aborting on container exit..." right before stop —
	# even on success it reads like a failure. The verdict line overrides.
	# Cleanup only on success — keep containers for inspection on failure.
	# `do | complete` instead of dind-vrun so the verdict still prints
	# if the cleanup itself fails.
	if $exit_code == 0 {
		let cleanup = (do { ^docker compose down -v --timeout 0 --remove-orphans } | complete)
		print $"(ansi green_bold)integrate ✓ passed(ansi reset)"
		if $cleanup.exit_code != 0 {
			print -e $"(ansi yellow_bold)cleanup warning(ansi reset): `docker compose down` exited ($cleanup.exit_code) — run 'docker compose down -v' manually if containers persist."
		}
	} else {
		print -e $"(ansi red_bold)integrate ✗ failed(ansi reset) — containers left for inspection; run 'docker compose logs' or 'docker compose down -v' when done."
		exit $exit_code
	}
}
