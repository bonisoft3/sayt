use std/assert
use dind.nu [parse-host-ip, parse-buildx-name, bounded-slug, cache-scope, cache_scope_max]
use tools.nu [is-secret-key]

# Fixtures captured by running `hostname -i` in real containers (see host-ip):
#   docker bridge net            → "172.17.0.5\n"        (single IP)
#   docker run --network=host    → "192.168.65.3\n"      (single IP)
#   multi-homed host (the regression) → space-separated IPs + TRAILING SPACE
# parse-host-ip must return the first IP for all of these, and "" when there is none.

def test_bridge_single_ip [] {
	assert equal (parse-host-ip "172.17.0.5\n") "172.17.0.5"
}

def test_hostnet_single_ip [] {
	assert equal (parse-host-ip "192.168.65.3\n") "192.168.65.3"
}

# The regression: old `split " " | last` grabbed the empty trailing token here.
def test_multi_homed_trailing_space [] {
	assert equal (parse-host-ip "192.168.65.3 192.168.65.6 172.17.0.1 \n") "192.168.65.3"
}

def test_single_ip_trailing_space [] {
	assert equal (parse-host-ip "192.168.65.3 \n") "192.168.65.3"
}

def test_empty [] {
	assert equal (parse-host-ip "") ""
}

def test_whitespace_only [] {
	assert equal (parse-host-ip "  \n ") ""
}

# Fixture: real `docker buildx inspect` output (single-node docker driver).
def test_buildx_name_single_node [] {
	assert equal (parse-buildx-name "Name:          desktop-linux\nDriver:        docker\nLast Activity: 2026-07-30 20:29:35 +0000 UTC\n\nNodes:\nName:             desktop-linux\nEndpoint:         desktop-linux\nStatus:           running\n") "desktop-linux"
}

# The builder's own Name: line must win over a differently-named node's —
# proves the selection picks the first match, not just any match.
def test_buildx_name_multi_node_distinct_names [] {
	assert equal (parse-buildx-name "Name:   mybuilder\nDriver: docker-container\n\nNodes:\nName:      mybuilder0\nEndpoint:  unix:///var/run/docker.sock\n\nName:      mybuilder1\nEndpoint:  ssh://otherhost\n") "mybuilder"
}

def test_buildx_name_missing [] {
	assert equal (parse-buildx-name "Driver: docker\n") ""
}

def test_buildx_name_empty [] {
	assert equal (parse-buildx-name "") ""
}

# vrun echoes an `export KEY=value` diagnostic preamble, and secret values
# must be redacted so the HOST_ENV projection (DOCKER_AUTH_CONFIG registry
# creds, KUBECONFIG_DATA client keys, depot tokens) never reaches CI logs.
# is-secret-key is the redaction predicate driving that.
def test_is_secret_key [] {
	# The projection carriers + common credential name patterns → redacted.
	for k in ["HOST_ENV" "DOCKER_AUTH_CONFIG" "KUBECONFIG_DATA" "DEPOT_TOKEN" "ACTIONS_RUNTIME_TOKEN" "MY_SECRET" "REGISTRY_PASSWORD" "GH_AUTH_TOKEN"] {
		assert (is-secret-key $k) $"($k) must be treated as secret"
	}
	# Ordinary build/config vars → shown verbatim.
	for k in ["COMPOSE_BAKE" "BUILDX_INSTANCE" "CACHE_SCOPE" "DOCKER_HOST" "SAYT_PLATFORM" "PATH"] {
		assert (not (is-secret-key $k)) $"($k) must NOT be redacted"
	}
}

# CACHE_SCOPE's length ceiling is a contract, not a convention: bayt's
# #cacheTagSeg budgets per-target segments as `62 - len(<project scope>)`
# assuming it holds. Every scope must honour it for any input, whether the
# engine is probed from a local builder or declared by the sayt/depot action.
const pathological_branches = [
	"main"
	"refs/heads/feat/short"
	"refs/heads/feat/a-quite-long-feature-branch-name-that-keeps-going-and-going"
	"feat/wild~^:?*[]chars"
	""
]
const pathological_engines = [
	"bk0.30.0-builtin-linux-amd64"
	"bk0.30.0-df1.24.0-labs-experimental-variant-linux-amd64"
	"depot-f5k5087x1b-df87999aa3d42b"
]

def test_bounded_slug_is_identity_when_it_fits [] {
	assert equal (bounded-slug "short" 64) "short"
	assert equal (bounded-slug ("x" | fill -c "x" -w 64) 64) ("x" | fill -c "x" -w 64)
}

def test_bounded_slug_caps_exactly_and_is_stable [] {
	let long = ("y" | fill -c "y" -w 200)
	assert equal (bounded-slug $long 64 | str length) 64
	assert equal (bounded-slug $long 64) (bounded-slug $long 64)
	# Distinct inputs sharing a prefix must not collide.
	assert ((bounded-slug $"($long)a" 64) != (bounded-slug $"($long)b" 64))
}

def test_cache_scope_respects_the_ceiling [] {
	for branch in $pathological_branches {
		for engine in $pathological_engines {
			let ns = (cache-scope $engine $branch)
			assert (($ns.scope | str length) <= $cache_scope_max) $"scope over cap: ($ns.scope)"
			assert (($ns.fallback | str length) <= $cache_scope_max) $"fallback over cap: ($ns.fallback)"
		}
	}
}

# `main` must scope to exactly its own fallback, or trunk writes a cache no
# branch can read back.
def test_trunk_scope_equals_its_fallback [] {
	for engine in $pathological_engines {
		let ns = (cache-scope $engine "refs/heads/main")
		assert equal $ns.scope $ns.fallback
	}
}


def main [] {
	test_bridge_single_ip
	test_hostnet_single_ip
	test_multi_homed_trailing_space
	test_single_ip_trailing_space
	test_empty
	test_whitespace_only
	test_buildx_name_single_node
	test_buildx_name_multi_node_distinct_names
	test_buildx_name_missing
	test_buildx_name_empty
	test_is_secret_key
	test_bounded_slug_is_identity_when_it_fits
	test_bounded_slug_caps_exactly_and_is_stable
	test_cache_scope_respects_the_ceiling
	test_trunk_scope_equals_its_fallback

	print "dind_test: all passed"
}
