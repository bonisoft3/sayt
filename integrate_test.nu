use std/assert
use integrate.nu [resolve-plan strip-bake-flags wants-session exports-cache target-batches]

def test_target_batches_bound_parallel_stacks_without_dropping_targets [] {
	assert equal (target-batches [a b c d e] 2) [[a b] [c d] [e]]
	assert equal (target-batches [a b c] 1) [[a] [b] [c]]
	assert equal (target-batches [a b] 3) [[a b]]
	assert error { target-batches [a] 0 }
}

# resolve-plan is pure — the axis grammar, verifiable without docker.

def test_default_is_compose_up [] {
	let p = (resolve-plan {})
	assert equal $p.build "compose"
	assert equal $p.up true
	assert equal $p.docker false
}

def test_bake_defaults_to_up [] {
	# bare --bake = bake THEN up (design §1).
	let p = (resolve-plan {bake: true})
	assert equal $p.build "bake"
	assert equal $p.up true
}

def test_bake_no_up_is_envelope [] {
	# --bake --no-up = bake alone (the envelope; exit code is the verdict).
	let p = (resolve-plan {bake: true, no_up: true})
	assert equal $p.build "bake"
	assert equal $p.up false
}

def test_no_build [] {
	let p = (resolve-plan {no_build: true})
	assert equal $p.build "none"
	assert equal $p.up true
}

def test_depot [] {
	assert equal (resolve-plan {depot: true}).build "depot"
}

def test_with_docker_bridges_the_daemon [] {
	# --with-docker hands a build RUN the host daemon, and nothing else.
	let p = (resolve-plan {with_docker: true})
	assert equal $p.docker true
	assert equal $p.buildx false
}

def test_buildx_implies_bridge [] {
	# --with-buildx pulls in --with-docker (builder ⇒ socat); reverse does not.
	let p = (resolve-plan {with_buildx: true})
	assert equal $p.buildx true
	assert equal $p.docker true
	assert equal (resolve-plan {with_docker: true}).buildx false
}

def test_capabilities_additive [] {
	let p = (resolve-plan {bake: true, with_kube: true, with_testcontainers: true})
	assert equal $p.kube true
	assert equal $p.testcontainers true
}

def test_testcontainers_opens_session_without_a_bake [] {
	# Gating the session on the bake axis alone made --with-testcontainers a
	# silent no-op on a --no-build runtime.
	assert equal (wants-session (resolve-plan {no_build: true, with_testcontainers: true})) true
	assert equal (wants-session (resolve-plan {no_build: true})) false
	assert equal (wants-session (resolve-plan {bake: true})) true
	assert equal (wants-session (resolve-plan {with_host_env: true})) true
}

def test_build_axis_single_valued [] {
	# Conflicting build flags must error, not silently pick one.
	let r = (try { resolve-plan {bake: true, depot: true}; "no-error" } catch { "errored" })
	assert equal $r "errored"
}

# strip-bake-flags drops bake-only flags from the non-bake compose-up
# passthrough, keeping compose-valid args (see integrate.nu).
def test_strip_bake_set [] {
	assert equal (strip-bake-flags ["--set" "*.cache-to="]) []
}

def test_strip_bake_keeps_compose_flags [] {
	assert equal (strip-bake-flags ["--set" "*.cache-to=" "--scale" "integrate=1"]) ["--scale" "integrate=1"]
}

def test_strip_bake_eq_form [] {
	# --set=VALUE is one token; strip just it, keep the rest.
	assert equal (strip-bake-flags ["--set=*.cache-to=" "-d"]) ["-d"]
}

def test_strip_bake_noop [] {
	assert equal (strip-bake-flags ["-d" "--scale" "web=2"]) ["-d" "--scale" "web=2"]
}

# Opting a project into a registry cache (bayt's sayt.depot) made every local
# bake export to that registry, and a developer without its credentials failed
# the build on the push. Only CI, or a run holding a depot token, writes.
def test_only_ci_or_a_depot_token_exports_cache [] {
	assert equal (exports-cache {}) false
	assert equal (exports-cache {CI: ""}) false
	assert equal (exports-cache {CI: "true"}) true
	assert equal (exports-cache {DEPOT_TOKEN: "t"}) true
}

def main [] {
	test_target_batches_bound_parallel_stacks_without_dropping_targets
	test_default_is_compose_up
	test_bake_defaults_to_up
	test_bake_no_up_is_envelope
	test_no_build
	test_depot
	test_with_docker_bridges_the_daemon
	test_buildx_implies_bridge
	test_capabilities_additive
	test_build_axis_single_valued
	test_strip_bake_set
	test_strip_bake_keeps_compose_flags
	test_strip_bake_eq_form
	test_strip_bake_noop
	test_only_ci_or_a_depot_token_exports_cache
	print "integrate_test: all passed"
}
