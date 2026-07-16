# integrate.nu — Integration testing workflow.
#
# Two orthogonal axes, set per project via `say.integrate.args` in .say.yaml:
#   * build — compose (default) | --bake | --depot | --no-build. Bake builds
#     run against a `docker compose config`-flattened file; --builder picks
#     the buildx builder.
#   * up — on by default: `docker compose up <target>` runs the integrate
#     service with compose-runtime semantics (entrypoint, network, volumes,
#     testcontainers shadows). --no-up stops after the build; `--bake --no-up`
#     is the envelope — the test runs inside the bake target's RUN, bake's
#     exit code is the verdict, and output stays `type=cacheonly`.
# The capability flags (--dind*, --with-*) collect host facilities into the
# sandbox via dind.nu's bridge.

use tools.nu [run-docker run-docker-compose run-live]
use compose.nu [compose-vrun compose-vup]
use dind.nu

# Pure (so integrate_test.nu covers it without docker): axis flags → plan.
# Single-valued build axis defaulting to `compose`.
export def resolve-plan [flags: record]: nothing -> record {
	mut picks = []
	if ($flags.bake? | default false) { $picks = ($picks | append "bake") }
	if ($flags.depot? | default false) { $picks = ($picks | append "depot") }
	if ($flags.no_build? | default false) { $picks = ($picks | append "none") }
	if ($picks | length) > 1 {
		error make {msg: $"integrate: build axis is single-valued; got conflicting flags → (($picks | str join ', ')). Pick one of --bake / --depot / --no-build."}
	}
	{
		build: ($picks | get 0? | default "compose")  # compose | bake | depot | none
		up: (not ($flags.no_up? | default false))
		dind_run: ($flags.dind? | default false)
		# --with-buildx ⇒ --dind-bridge: the injected builder is only reachable
		# through the bridged daemon (the builder ⇒ socat invariant).
		dind_bridge: (($flags.dind_bridge? | default false) or ($flags.with_buildx? | default false))
		buildx: ($flags.with_buildx? | default false)
		kube: ($flags.with_kube? | default false)
		testcontainers: ($flags.with_testcontainers? | default false)
		host_env: ($flags.with_host_env? | default false)
	}
}

# Bake-only passthrough flags (from `buildx bake --help`, minus the flags sayt
# owns: -f/--builder/--progress/--no-cache). The value marks flags that consume
# the following token when the value isn't inline (--set foo= vs --set=foo=).
const bake_flags = {
	"--set": true, "--allow": true, "--call": true, "--metadata-file": true,
	"--check": false, "--load": false, "--print": false, "--provenance": false,
	"--pull": false, "--push": false, "--sbom": false,
}

# Pure (integrate_test.nu): route ...args for a dual-phase run — whitelisted
# bake flags (+ their values) → .bake, everything else → .up (compose up's).
export def split-bake-args [args: list<string>]: nothing -> record {
	mut bake = []
	mut up = []
	mut i = 0
	while $i < ($args | length) {
		let arg = ($args | get $i)
		let name = ($arg | split row "=" | first)
		if $name in $bake_flags {
			$bake = ($bake | append $arg)
			if ($bake_flags | get $name) and (not ($arg | str contains "=")) and (($i + 1) < ($args | length)) {
				$bake = ($bake | append ($args | get ($i + 1)))
				$i = $i + 2
				continue
			}
		} else {
			$up = ($up | append $arg)
		}
		$i = $i + 1
	}
	{bake: $bake, up: $up}
}

# Caller env var wins over the session-derived fallback when set non-empty.
def env-or [name: string, fallback: string]: nothing -> string {
	let v = ($env | get --optional $name | default "")
	if ($v | is-empty) { $fallback } else { $v }
}

# Down stacks left by failed runs in ANY compose project — the clean
# slate in `main` is per-project. The compose-stamped `integrate`
# service label marks a stack as sayt's.
def reap-integrate-stacks [] {
	let names = (do { ^docker ps -a --filter label=com.docker.compose.service=integrate --format '{{.Label "com.docker.compose.project"}}' } | complete)
	for n in ($names.stdout | lines | uniq) {
		print -e $"sayt: tearing down leftover compose project '($n)'"
		do { ^docker compose -p $n down -v --timeout 0 --remove-orphans } | complete | ignore
	}
}

export def --wrapped main [
	--target: string = "integrate" # Comma separated list of compose services/bake targets. Sometimes your services hit buildkit 4mb grpc cap, and you can sidestep it by feeding multiple targets.
	--no-cache        # Build without cache
	--no-cache-from   # Suppress all cache-from import (outer + inner); local escape hatch for runs without registry auth. (SAYT_NO_CACHE_FROM env suppresses only the inner.)
	--no-cache-to     # Suppress all cache-to export (outer + inner); local escape hatch for runs without registry auth. (SAYT_NO_CACHE_TO env suppresses only the inner.)
	--progress: string = "auto" # Progress output (auto/plain/tty)
	--bake            # build via `docker buildx bake` (build axis)
	--depot           # bake with DEPOT_* in the session so the inner bake runs `depot bake` (build axis; needs DEPOT_PROJECT_ID). The outer command is the same `docker buildx bake` as --bake.
	--no-build        # skip build; `compose up --no-build` (images must pre-exist)
	--no-up           # stop after the build (don't compose up). `--bake --no-up` = the envelope: the test runs in the bake RUN and bake's exit code is the verdict.
	--dind            # runtime `compose up` gets a daemon: inject ${DOCKER_HOST:-unix:///var/run/docker.sock}
	--dind-bridge     # a build RUN gets a daemon (socat tcp bridge) — ability to run containers
	--with-buildx     # inject the host buildx builder into a build RUN — ability to bake (implies --dind-bridge)
	--with-kube       # collect host kubeconfig into the sandbox (KUBECONFIG_DATA)
	--with-testcontainers  # provision testcontainers: reachable daemon + host override
	--with-host-env   # compose path: graph env-sources HOST_ENV → open a dind bridge
	--builder: string # names the buildx builder to inject (--with-buildx) and/or drive the outer bake
	...args           # Additional flags passed to compose up or bake
] {
	let plan = (resolve-plan {
		bake: $bake
		depot: $depot
		no_build: $no_build
		no_up: $no_up
		dind: $dind
		dind_bridge: $dind_bridge
		with_buildx: $with_buildx
		with_kube: $with_kube
		with_testcontainers: $with_testcontainers
		with_host_env: $with_host_env
	})
	let is_bake = ($plan.build in ["bake" "depot"])
	let targets = ($target | split row ",")
	if (not $is_bake) and ($targets | length) > 1 {
		error make {msg: $"multi-target --target only supported with a bake build; got ($targets | length) targets in compose mode"}
	}
	# Route ...args once. Single-phase runs hand the whole spread to their one
	# tool (envelope → bake, compose → compose up, 0.20.x-compatible); a
	# dual-phase bake splits it: whitelisted bake flags → bake, rest → up.
	let raw_args = if ($args | length) > 0 and ($args | first) == "--" { $args | skip 1 } else { $args }
	let routed = (split-bake-args $raw_args)
	let bake_passthrough = if $plan.up { $routed.bake } else { $raw_args }
	let up_args = if ($is_bake and $plan.up) { $routed.up } else { $raw_args }
	reap-integrate-stacks
	if $is_bake {
		# integrate owns dind policy. auth rides --bake; the
		# RUN's daemon (--dind-bridge) and builder (--with-buildx, named by
		# --builder) are explicit; gha/depot/frontend auto-forward from host env.
		let dind_builder = if $plan.buildx { ($builder | default "") } else { "" }
		let want_gha = ("ACTIONS_CACHE_URL" in $env) and ("ACTIONS_RUNTIME_TOKEN" in $env)
		# depot: the --depot axis, or an ambient DEPOT_TOKEN (the depot CI action
		# sets it to route the inner bake to depot).
		let want_depot = ($plan.build == "depot") or ($env.DEPOT_TOKEN? | default "" | is-not-empty)
		let want_frontend = ($env.BUILDKIT_SYNTAX? | default "" | is-not-empty)
		let session = (dind bridge open
			--auth
			--socat=($plan.dind_bridge)
			--builder $dind_builder
			--gha=$want_gha
			--depot=$want_depot
			--frontend=$want_frontend
			--kube=($plan.kube)
			--testcontainers=($plan.testcontainers))
		# The bake env spreads the dind session ABI as a unit — DOCKER_HOST_TCP,
		# DOCKER_AUTH_CONFIG, BUILDX_*, CACHE_SCOPE*, KUBECONFIG_DATA,
		# TESTCONTAINERS_HOST_OVERRIDE, DEPOT_*, BUILDKIT_SYNTAX — which bayt's inject
		# step materializes as /run/secrets/<x> files in the inner sandbox. Only the
		# vars below are computed here; HOST_ENV (the env-file projection) is
		# compose-path only, never a bake input.
		let session_env = $session.env

		# `--allow=fs.read=<worktree-root>` (passed into bake below) silences bake's
		# fs-entitlement warning for contexts outside the bake file's dir. `git
		# rev-parse --show-toplevel` is load-bearing for git worktrees.
		let worktree_root = (^git rev-parse --show-toplevel | str trim)
		let tmpdir = (^mktemp -d | str trim)
		let flat_compose = $"($tmpdir)/compose.yaml"

		# Invocation-local vars merged over the session ABI. DOCKER_HOST_TCP
		# (not DOCKER_HOST) stays from the session: the sandbox's inject body extracts
		# it into $DOCKER_HOST — setting DOCKER_HOST here would point the outer bake CLI
		# at a VM-only tcp endpoint.
		let local_env = {
			# A caller can route the inner builder elsewhere (e.g. depot's
			# ~/.docker/buildx/instances/depot_<proj>) without touching --builder; the
			# instance file's "Endpoint" is pre-rewritten to the socat tcp endpoint so
			# the sandbox's context-less buildx can resolve it.
			BUILDX_INSTANCE: (env-or "BUILDX_INSTANCE" $session_env.BUILDX_INSTANCE),
			BUILDX_BUILDER: (env-or "BUILDX_BUILDER" $session_env.BUILDX_BUILDER),
			# --no-cache expands to `--no-cache --set *.cache-from= --set *.cache-to=`
			# in the inner bake's do-script. SAYT_NO_CACHE_{FROM,TO} suppress the inner
			# only (a separate writer owns the cache); --no-cache-{from,to} also strip
			# the outer refs below.
			SAYT_NO_CACHE: (if $no_cache { "1" } else { "" }),
			SAYT_NO_CACHE_FROM: (if ($no_cache_from or (($env.SAYT_NO_CACHE_FROM? | default "") | is-not-empty)) { "1" } else { "" }),
			SAYT_NO_CACHE_TO: (if ($no_cache_to or (($env.SAYT_NO_CACHE_TO? | default "") | is-not-empty)) { "1" } else { "" }),
			BAYT_IMAGE_TAG: ($env.BAYT_IMAGE_TAG? | default ""),
			BAYT_PULL_POLICY: ($env.BAYT_PULL_POLICY? | default ""),
			DEPOT_DISABLE_OTEL: "1",
			BUILDX_NO_DEFAULT_ATTESTATIONS: "1",
			# SOURCE_DATE_EPOCH pins manifest timestamps (stable digests);
			# BUILDX_BAKE_ENTITLEMENTS_FS clears the fs-read block for the /tmp flat
			# compose's out-of-dir contexts.
			SOURCE_DATE_EPOCH: "0",
			BUILDX_BAKE_ENTITLEMENTS_FS: "0",
		}
		let bake_exit = with-env ($session_env | merge $local_env) {
			# Flatten the compose graph before bake: compose's include resolution
			# dedupes services that appear in multiple included files (e.g. shared
			# bayt-runtime-stub); bake otherwise errors with "services.X conflicts
			# with imported resource". --profile "*": root aliases are profile-gated
			# (gen_compose compose.root); without it they drop out of the flat file
			# and bake fails to find the target.
			let cfg_exit = (run-live docker compose --profile "*" config -o $flat_compose)
			if $cfg_exit != 0 {
				print -e $"docker compose config exited ($cfg_exit)"
				$cfg_exit
			} else {
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
				# Outer keeps cache-from/cache-to (reads + memoizes on its local
				# builder) unless --no-cache-from / --no-cache-to is set (local runs
				# with no registry auth).
				let no_cache_from_args = if $no_cache_from { ["--set", "*.cache-from="] } else { [] }
				let no_cache_to_args = if $no_cache_to { ["--set", "*.cache-to="] } else { [] }
				# Frontend selection, per invocation: the built-in frontend
				# delegates to the image named by the BUILDKIT_SYNTAX
				# build-arg. The arg must be ABSENT (not empty) when
				# unpinned — an empty value fails the build with "invalid
				# reference format" — hence a conditional --set instead of
				# a generated compose arg with an empty default.
				let syntax_args = if ($session_env.BUILDKIT_SYNTAX | is-empty) { [] } else {
					["--set", $"*.args.BUILDKIT_SYNTAX=($session_env.BUILDKIT_SYNTAX)"]
				}
				# --up loads images (type=docker) for the compose up below; --no-up
				# is the envelope — the test is the bake RUN itself, so cacheonly.
				let output_set = if $plan.up { ["--set", "*.output=type=docker"] } else { ["--set", "*.output=type=cacheonly"] }
				let bake_args = ($builder_args ++ $syntax_args ++ [
					$"--allow=fs.read=($worktree_root)",
					"-f", $flat_compose,
					"--progress", $progress
				] ++ $output_set ++ $no_cache_args ++ $no_cache_from_args ++ $no_cache_to_args) ++ $bake_passthrough ++ $targets
				# Load-bearing ordering: the flatten above interpolated
				# ${CACHE_SCOPE} into the x-bake refs with the OUTER value;
				# bayt's env-sourced cache_scope secret resolves HERE, at
				# bake invocation, so this nested env hands the INNER scope
				# (caller INNER_CACHE_SCOPE wins, else the outer's) to the
				# sandbox without touching the outer refs.
				with-env {
					CACHE_SCOPE: (env-or "INNER_CACHE_SCOPE" $session_env.CACHE_SCOPE),
					CACHE_SCOPE_FALLBACK: (env-or "INNER_CACHE_SCOPE_FALLBACK" $session_env.CACHE_SCOPE_FALLBACK),
				} {
					run-live docker buildx bake ...$bake_args
				}
			}
		}
		rm -rf $tmpdir
		dind bridge close $session

		if $bake_exit != 0 {
			print -e $"(ansi red_bold)integrate ✗ failed(ansi reset)"
			exit $bake_exit
		}
		# Envelope: nothing was loaded to run.
		if not $plan.up {
			print $"(ansi green_bold)integrate ✓ passed(ansi reset)"
			return
		}
		# --up: images are loaded; fall through to run them (compose up --no-build).
		print -e $"(ansi green_bold)bake ✓(ansi reset) — running compose up against the loaded images"
	}

	# `compose` builds the graph; `none` and a bake/depot --up fall-through both
	# run pre-existing images (bake loaded them above).
	let compose_build_flag = if $plan.build == "compose" { "--build" } else { "--no-build" }

	# --no-up here (non-bake): build only, don't run. `none --no-up` is a no-op.
	if not $plan.up {
		if $plan.build == "compose" {
			with-env {BUILDX_NO_DEFAULT_ATTESTATIONS: "1"} {
				compose-vrun --host-env=($plan.host_env) docker compose build --progress $progress $target ...$args
			}
		}
		print $"(ansi green_bold)integrate ✓ built(ansi reset) (--no-up)"
		return
	}

	# --dind: expose DOCKER_HOST to the runtime compose up. Services opt in with
	# `${DOCKER_HOST:-unix:///var/run/docker.sock}`; a tcp:// host flows through.
	let dind_env = if $plan.dind_run {
		{DOCKER_HOST: ($env.DOCKER_HOST? | default "unix:///var/run/docker.sock")}
	} else { {} }

	# Clean slate: remove any leftover containers from previous runs.
	run-docker-compose down -v --timeout 0 --remove-orphans

	# Disable buildkit's default provenance + SBOM attestations: they
	# embed wall-clock timestamps in image manifests, drifting digests
	# across runs. For chained bayt targets (one FROMs another), that
	# drift cascades into cache misses on downstream RUNs.
	let exit_code = with-env ({BUILDX_NO_DEFAULT_ATTESTATIONS: "1"} | merge $dind_env) {
		if $no_cache and ($plan.build == "compose") {
			compose-vrun --host-env=($plan.host_env) docker compose build --no-cache $target
		}
		# `compose up` has no --progress flag (only `compose build`
		# does); when --no-cache is set, the build above already
		# honored $progress.
		compose-vup --host-env=($plan.host_env) $target --abort-on-container-failure --exit-code-from $target --force-recreate $compose_build_flag --renew-anon-volumes --remove-orphans --attach-dependencies ...$up_args
		$env.LAST_EXIT_CODE
	}

	# Explicit pass/fail verdict. `compose up --exit-code-from` always
	# emits a red "Aborting on container exit..." right before stop —
	# even on success it reads like a failure. The verdict line overrides.
	# Cleanup only on success — keep containers for inspection on failure.
	# `do | complete` instead of compose-vrun so the verdict still prints
	# if the cleanup itself fails.
	if $exit_code == 0 {
		let cleanup = (do { ^docker compose down -v --timeout 0 --remove-orphans } | complete)
		print $"(ansi green_bold)integrate ✓ passed(ansi reset)"
		if $cleanup.exit_code != 0 {
			print -e $"(ansi yellow_bold)cleanup warning(ansi reset): `docker compose down` exited ($cleanup.exit_code) — run 'docker compose down -v' manually if containers persist."
		}
	} else {
		print -e $"(ansi red_bold)integrate ✗ failed(ansi reset) — containers left for inspection; run 'docker compose logs' or 'docker compose down -v' when done \(the next sayt integrate cleans them up automatically\)."
		exit $exit_code
	}
}
