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
	--target: string = "integrate" # Comma separated list of compose services/bake targets. Sometimes your services hit buildkit 4mb grpc cap, and you can sidestep it by feeding multiple targets.
	--no-cache        # Build without cache
	--no-cache-to     # Suppress all cache-to export (outer + inner); local escape hatch for runs without registry auth. (SAYT_NO_CACHE_TO env suppresses only the inner.)
	--progress: string = "auto" # Progress output (auto/plain/tty)
	--bake            # Use docker buildx bake instead of compose
	--builder: string # buildx builder for --bake (e.g. "container", "depot")
	...args           # Additional flags passed to compose up or bake
] {
	let targets = ($target | split row ",")
	if (not $bake) and ($targets | length) > 1 {
		error make {msg: $"multi-target --target only supported with --bake; got ($targets | length) targets in compose mode"}
	}
	if $bake {
		# Flatten the compose graph via `docker compose config` before
		# bake. compose's include resolution dedupes services that
		# appear in multiple included files (e.g. shared bayt-runtime-
		# stub); bake otherwise errors with "services.X conflicts with
		# imported resource".
		let _t_start = (date now)
		let host_env = (dind env-file --socat --builder ($builder | default ""))
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
		# CACHE_SCOPE / CACHE_SCOPE_FALLBACK from the dind-emitted
		# host.env: the OUTER builder's identity, interpolated into the
		# x-bake refs by `docker compose config` below.
		let cache_scope_val = ($host_env | lines | where $it =~ "^CACHE_SCOPE=" | first | default "CACHE_SCOPE=" | split row "=" | skip 1 | str join "=")
		let cache_scope_fallback_val = ($host_env | lines | where $it =~ "^CACHE_SCOPE_FALLBACK=" | first | default "CACHE_SCOPE_FALLBACK=" | split row "=" | skip 1 | str join "=")
		# The host decides the inner's builder (caller-set
		# BUILDX_INSTANCE / BUILDX_BUILDER can route it to depot), so
		# the host decides the inner's scope too: caller-set
		# INNER_CACHE_SCOPE wins, else the inner shares the outer's
		# builder and scope. Never derived in-sandbox.
		let inner_scope_val = ($env.INNER_CACHE_SCOPE? | default $cache_scope_val)
		let inner_scope_fallback_val = ($env.INNER_CACHE_SCOPE_FALLBACK? | default $cache_scope_fallback_val)
		# SAYT_BUILDKIT_SYNTAX — external dockerfile frontend pin from
		# the CI action (empty locally → builtin frontend). Applied to
		# the outer bake below and threaded to the inner via its
		# compose secret.
		let buildkit_syntax_val = ($env.SAYT_BUILDKIT_SYNTAX? | default "")
		# BAYT_IMAGE_TAG / BAYT_PULL_POLICY — the host decides image
		# tag and pull policy; this block only transports. Empty
		# degrades to latest/build.
		let bayt_image_tag_val = ($env.BAYT_IMAGE_TAG? | default "")
		let bayt_pull_policy_val = ($env.BAYT_PULL_POLICY? | default "")
		# Two cache-to suppression scopes, transport-only (no depot/branch
		# knowledge here — callers decide):
		#   * the --no-cache-to flag suppresses BOTH outer and inner: the local
		#     escape hatch for skipping registry pushes you aren't authed for.
		#   * SAYT_NO_CACHE_TO env suppresses the INNER only; the outer keeps
		#     memoizing. Callers set it when a separate writer owns the cache.
		let inner_no_cache_to = $no_cache_to or (($env.SAYT_NO_CACHE_TO? | default "") | is-not-empty)
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
			SAYT_BUILDKIT_SYNTAX: $buildkit_syntax_val,
			# SAYT_NO_CACHE — propagates --no-cache through the
			# dindbox compose-secret chain into the inner bake's
			# `do` script, where it expands to `--no-cache --set
			# "*.cache-from=" --set "*.cache-to="`. Disables both
			# cache import and export at the inner level.
			SAYT_NO_CACHE: (if $no_cache { "1" } else { "" }),
			SAYT_NO_CACHE_TO: (if $inner_no_cache_to { "1" } else { "" }),
			BAYT_IMAGE_TAG: $bayt_image_tag_val,
			BAYT_PULL_POLICY: $bayt_pull_policy_val,
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
			# `try { ^cmd } catch { |err| $err.exit_code }` streams the
			# command's stdout/stderr live AND captures its exit code.
			# Bare `^cmd` raises mid-block on non-zero exit (skipping the
			# `let exit = $env.LAST_EXIT_CODE` below) and `do { ... } |
			# complete` works but buffers everything until the command
			# exits — kills live `--progress=plain` output during long bake
			# runs. The `try`/`catch`/`err.exit_code` form is the streaming
			# equivalent of `complete`.
			let cfg_exit = (try { ^docker compose config -o $flat_compose; 0 } catch { |err| $err.exit_code })
			if $cfg_exit != 0 {
				rm -rf $tmpdir
				print -e $"(ansi red_bold)integrate ✗ failed(ansi reset) — docker compose config exited ($cfg_exit)"
				exit $cfg_exit
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
			# Outer keeps cache-to (memoizes on its local builder) unless
			# --no-cache-to is set (local runs with no registry auth).
			let no_cache_to_args = if $no_cache_to { ["--set", "*.cache-to="] } else { [] }
			# Frontend selection, per invocation: the built-in frontend
			# delegates to the image named by the BUILDKIT_SYNTAX
			# build-arg. The arg must be ABSENT (not empty) when
			# unpinned — an empty value fails the build with "invalid
			# reference format" — hence a conditional --set instead of
			# a generated compose arg with an empty default.
			let syntax_args = if ($buildkit_syntax_val | is-empty) { [] } else {
				["--set", $"*.args.BUILDKIT_SYNTAX=($buildkit_syntax_val)"]
			}
			let bake_args = ($builder_args ++ $syntax_args ++ [
				$"--allow=fs.read=($worktree_root)",
				"-f", $flat_compose,
				"--set", "*.output=type=cacheonly",
				"--progress", $progress
			] ++ $no_cache_args ++ $no_cache_to_args) ++ $passthrough ++ $targets
			# Load-bearing timing split: the flatten above interpolated
			# ${CACHE_SCOPE} into the x-bake refs with the OUTER value;
			# bayt's env-sourced cache_scope secret resolves HERE, at
			# bake invocation, so this nested env hands the INNER scope
			# to the sandbox without touching the outer refs.
			let bake_inner_exit = (with-env {
				CACHE_SCOPE: $inner_scope_val,
				CACHE_SCOPE_FALLBACK: $inner_scope_fallback_val,
			} {
				try { ^docker buildx bake ...$bake_args; 0 } catch { |err| $err.exit_code }
			})
			rm -rf $tmpdir
			$bake_inner_exit
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
