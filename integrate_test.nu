use std/assert
use integrate.nu [resolve-plan strip-bake-flags]

# resolve-plan is pure — the axis grammar, verifiable without docker.

def test_default_is_compose_up [] {
	let p = (resolve-plan {})
	assert equal $p.build "compose"
	assert equal $p.up true
	assert equal $p.dind_run false
	assert equal $p.dind_bridge false
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

def test_dind_run_and_bridge_independent [] {
	# runtime daemon (--dind) and build-RUN daemon (--dind-bridge) are separate.
	let p = (resolve-plan {dind: true})
	assert equal $p.dind_run true
	assert equal $p.dind_bridge false
	let q = (resolve-plan {dind_bridge: true})
	assert equal $q.dind_run false
	assert equal $q.dind_bridge true
}

def test_buildx_implies_bridge [] {
	# --with-buildx pulls in --dind-bridge (builder ⇒ socat); reverse does not.
	let p = (resolve-plan {with_buildx: true})
	assert equal $p.buildx true
	assert equal $p.dind_bridge true
	assert equal (resolve-plan {dind_bridge: true}).buildx false
}

def test_capabilities_additive [] {
	let p = (resolve-plan {bake: true, with_kube: true, with_testcontainers: true})
	assert equal $p.kube true
	assert equal $p.testcontainers true
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

def main [] {
	test_default_is_compose_up
	test_bake_defaults_to_up
	test_bake_no_up_is_envelope
	test_no_build
	test_depot
	test_dind_run_and_bridge_independent
	test_buildx_implies_bridge
	test_capabilities_additive
	test_build_axis_single_valued
	test_strip_bake_set
	test_strip_bake_keeps_compose_flags
	test_strip_bake_eq_form
	test_strip_bake_noop
	print "integrate_test: all passed"
}
