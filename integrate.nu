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
		# Prefer caller-set BUILDX_INSTANCE / BUILDX_BUILDER if present.
		# Lets a workflow override the inner's builder (e.g. point it at
		# depot via the host's `~/.docker/buildx/instances/depot_<proj>`
		# file) without touching the outer's --builder flag.
		# Rewrite the instance file's "Endpoint":"desktop-linux" (or
		# whatever docker-context name the host uses) to the tcp://
		# socat-bridged daemon endpoint. Inside the dindbox, buildx
		# resolves Endpoint against the local docker-context db; with
		# only a vanilla docker:cli image present, named contexts don't
		# exist there, so the unrewritten file errors with "context not
		# found". The tcp form is reachable through the socat bridge
		# and matches what DOCKER_HOST already points at.
		let buildx_instance_val = if ($env.BUILDX_INSTANCE? | default "" | is-not-empty) { $env.BUILDX_INSTANCE } else { dind buildx-instance-rewritten $builder --docker-host=$docker_host_val }
		let buildx_builder_val = if ($env.BUILDX_BUILDER? | default "" | is-not-empty) { $env.BUILDX_BUILDER } else { if ($builder | is-empty) { "" } else { $builder } }
		# Pull CACHE_SCOPE / CACHE_SCOPE_FALLBACK from the dind-emitted
		# host.env so the outer's `docker compose config` interpolates
		# the same scope identifier the dindbox-side compose config
		# will see. dind.buildx-fingerprint computes the version+platform
		# suffix from the actual buildx builder; BRANCH (or "main")
		# carries the per-branch dimension.
		let cache_scope_val = ($host_env | lines | where $it =~ "^CACHE_SCOPE=" | first | default "CACHE_SCOPE=" | split row "=" | skip 1 | str join "=")
		let cache_scope_fallback_val = ($host_env | lines | where $it =~ "^CACHE_SCOPE_FALLBACK=" | first | default "CACHE_SCOPE_FALLBACK=" | split row "=" | skip 1 | str join "=")
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
			CACHE_SCOPE: $cache_scope_val,
			CACHE_SCOPE_FALLBACK: $cache_scope_fallback_val,
			# SAYT_NO_CACHE — propagates --no-cache through the
			# dindbox compose-secret chain into the inner bake's
			# `do` script, where it expands to `--no-cache --set
			# "*.cache-from=" --set "*.cache-to="`. Disables both
			# cache import and export at the inner level.
			SAYT_NO_CACHE: (if $no_cache { "1" } else { "" }),
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
			# `do | complete` captures the external command's exit code
			# explicitly. The bare `^cmd` form's exit semantics depend on
			# whether nushell raises mid-block — observed false-greens when
			# bake's ResourceExhausted error surfaced in stderr but
			# `$env.LAST_EXIT_CODE` read as 0 below. Buffering stdout/stderr
			# trades live streaming for guaranteed exit-code propagation;
			# we replay them immediately so the user still sees the output.
			let cfg = (do { ^docker compose config -o $flat_compose } | complete)
			if ($cfg.stdout | is-not-empty) { print $cfg.stdout }
			if ($cfg.stderr | is-not-empty) { print -e $cfg.stderr }
			if $cfg.exit_code != 0 {
				rm -rf $tmpdir
				print -e $"(ansi red_bold)integrate ✗ failed(ansi reset) — docker compose config exited ($cfg.exit_code)"
				exit $cfg.exit_code
			}

			let passthrough = if ($args | length) > 0 and ($args | first) == "--" { $args | skip 1 } else { $args }
			let builder_args = if ($builder | is-empty) { [] } else { ["--builder", $builder] }
			# --no-cache: also strip the compose x-bake.cache-from /
			# cache-to refs at the outer level. `--no-cache` alone tells
			# buildkit "don't use cached layers" but it still configures
			# the registry importer for cache-from, which 401s on
			# unauthenticated repros. The SAYT_NO_CACHE env above does
			# the same suppression for the inner bake.
			let no_cache_args = if $no_cache {
				["--no-cache", "--set", "*.cache-from=", "--set", "*.cache-to="]
			} else { [] }
			let bake_args = ($builder_args ++ [
				$"--allow=fs.read=($worktree_root)",
				"-f", $flat_compose,
				"--set", "*.output=type=cacheonly",
				"--progress", $progress
			] ++ $no_cache_args) ++ $passthrough ++ [ $target ]
			let bake = (do { ^docker buildx bake ...$bake_args } | complete)
			if ($bake.stdout | is-not-empty) { print $bake.stdout }
			if ($bake.stderr | is-not-empty) { print -e $bake.stderr }
			rm -rf $tmpdir
			$bake.exit_code
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
