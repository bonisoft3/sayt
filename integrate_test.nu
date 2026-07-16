use std/assert
use integrate.nu [resolve-plan split-bake-args]

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

# split-bake-args routes a dual-phase run's passthrough: whitelisted bake
# flags (with their values) → bake, everything else → compose up.
def test_split_set_with_value [] {
	let r = (split-bake-args ["--set" "*.cache-to=" "--quiet-pull"])
	assert equal $r.bake ["--set" "*.cache-to="]
	assert equal $r.up ["--quiet-pull"]
}

def test_split_inline_value_form [] {
	let r = (split-bake-args ["--set=*.cache-to=" "--wait"])
	assert equal $r.bake ["--set=*.cache-to="]
	assert equal $r.up ["--wait"]
}

def test_split_boolean_bake_flag_takes_no_value [] {
	# --print is boolean: the following token is NOT its value.
	let r = (split-bake-args ["--print" "--quiet-pull"])
	assert equal $r.bake ["--print"]
	assert equal $r.up ["--quiet-pull"]
}

def test_split_value_flag_at_end_no_overrun [] {
	assert equal (split-bake-args ["--set"]).bake ["--set"]
}

def test_split_unknown_flags_go_up [] {
	let r = (split-bake-args ["--scale" "app=2" "--no-color"])
	assert equal $r.bake []
	assert equal $r.up ["--scale" "app=2" "--no-color"]
}

def main [] {
	test_split_set_with_value
	test_split_inline_value_form
	test_split_boolean_bake_flag_takes_no_value
	test_split_value_flag_at_end_no_overrun
	test_split_unknown_flags_go_up
	test_default_is_compose_up
	test_bake_defaults_to_up
	test_bake_no_up_is_envelope
	test_no_build
	test_depot
	test_dind_run_and_bridge_independent
	test_buildx_implies_bridge
	test_capabilities_additive
	test_build_axis_single_valued
	print "integrate_test: all passed"
}
