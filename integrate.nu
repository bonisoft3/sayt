# integrate.nu — Integration testing workflow.
#
# Two paths:
#   * default — `docker compose up <target>` against the per-project
#     compose graph. Builds + loads every stage as a docker image, runs
#     the requested service. The historical path; works for projects
#     whose integrate stage relies on compose-runtime semantics
#     (entrypoint, network, volumes — testcontainers shadows, etc.).
#   * --bake — `docker buildx bake` against a `docker compose
#     config`-flattened compose file, with --builder selectable so
#     callers can pick any buildx builder (default docker driver, a
#     docker-container builder, or a remote backend like depot.dev).
#     The integration test executes during the integrate stage's RUN
#     (inside `bake` itself), so bake's exit code IS the test verdict
#     — output is set to cacheonly since nothing needs to be loaded
#     into the docker image store and no compose `up` runs a
#     container. ~3-5× faster than compose mode on services/tracker.
#     Opt-in per project via `say.integrate.args: "--bake"` in
#     .say.yaml.

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
		# docker buildx bake doesn't dedupe services declared by
		# multiple included compose files (e.g. shared bayt-runtime-stub),
		# so bake-direct on .bayt/compose.yaml errors out with
		# "services.X conflicts with imported resource". Flatten via
		# `docker compose config` first — compose's include resolution
		# produces a single deduped service set that bake handles
		# cleanly.
		let _t_start = (date now)
		let host_env = (dind env-file --socat)
		let socat_id = ($host_env | lines | where $it =~ "SOCAT_CONTAINER_ID" | first | default "" | split row "=" | last)
		let host_env_file = (^mktemp)
		$host_env | save --force $host_env_file
		let _t_hostenv = (date now)
		print -e $"BAYT_TIMING bake host.env: (($_t_hostenv - $_t_start) / 1ms)ms"

		# Bake's filesystem-entitlement check fires when context paths
		# in the flattened compose resolve outside the bake file's dir
		# (we put the flat compose in /tmp/ but contexts resolve to the
		# worktree root). Without --allow, bake prints a long warning
		# and asks the user to retry with the suggested flag. Setting
		# BUILDX_BAKE_ENTITLEMENTS_FS=0 only suppresses the block, not
		# the warning. Passing --allow=fs.read=<worktree-root> silences
		# both. `git rev-parse --show-toplevel` correctly returns the
		# worktree root for git worktrees (not the main repo root).
		let worktree_root = (^git rev-parse --show-toplevel | str trim)

		let bake_exit = with-env {
			HOST_ENV: $host_env,
			BAYT_HOST_ENV_FILE: $host_env_file,
			BUILDX_NO_DEFAULT_ATTESTATIONS: "1",
			# The flat compose lives in a tempdir; bake's filesystem
			# entitlements check fires on any path outside the bake
			# file's dir. We pass --allow=fs.read for the worktree
			# root, but the tempdir itself can also trip the check.
			# `BUILDX_BAKE_ENTITLEMENTS_FS=0` disables the block
			# (warning still suppressed via the explicit --allow).
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

		rm -f $host_env_file
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

	# Clean slate: remove any leftover containers from previous runs
	run-docker-compose down -v --timeout 0 --remove-orphans

	# If --no-cache, build without cache first
	if $no_cache {
		dind-vrun docker compose build --no-cache $target
	}

	# Run compose with dind environment and capture exit code
	compose-vup --progress $progress $target --abort-on-container-failure --exit-code-from $target --force-recreate --build --renew-anon-volumes --remove-orphans --attach-dependencies ...$args
	let exit_code = $env.LAST_EXIT_CODE

	# Print an explicit verdict line. `docker compose up --exit-code-from`
	# always emits a red "Aborting on container exit..." right before stop,
	# even on success — visually it reads like a failure. Printing
	# pass/fail makes the actual outcome unambiguous and the cosmetic red
	# gets overshadowed.
	#
	# Only cleanup on success - on failure, keep containers for inspection.
	# Cleanup runs via `do | complete` (not dind-vrun, which exits on
	# non-zero) so the verdict still prints if cleanup itself fails.
	# `docker compose down` doesn't need the dind env (no host.env, no
	# socat) — stopping containers and removing networks is plain docker.
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
