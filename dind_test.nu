use std/assert
use dind.nu [parse-gateway-ip, loopback-addr, parse-buildx-name, bounded-slug, cache-scope, cache_scope_max]
use tools.nu [is-secret-key]

# Verbatim /etc/hosts from the real probe container (see gateway-ip). Note the
# shape, which is the whole reason this parse is anchored on the name: the
# gateway entry is neither first nor last, `127.0.0.1 localhost` leads, and the
# container's own address trails.
const HOSTS = "127.0.0.1\tlocalhost
::1\tlocalhost ip6-localhost ip6-loopback
fe00::\tip6-localnet
ff00::\tip6-mcastprefix
ff02::1\tip6-allnodes
ff02::2\tip6-allrouters
192.168.65.254\tgateway.docker.internal
172.17.0.4\t79fc6cc22d80
"

def test_gateway_ip_is_read_by_name_not_position [] {
	assert equal (parse-gateway-ip $HOSTS) "192.168.65.254"
}

# The Linux shape differs from the fixture above only in the address; both were
# measured (Docker Desktop 192.168.65.254, docker0 172.17.0.1).
def test_gateway_ip_linux_bridge [] {
	assert equal (parse-gateway-ip ($HOSTS | str replace "192.168.65.254" "172.17.0.1")) "172.17.0.1"
}

# Leading `127.0.0.1 localhost` must never be mistaken for the gateway — that is
# the address the old `hostname -i` probe returned on depot runners, and it
# reaches nothing from a build RUN.
def test_gateway_ip_never_returns_the_localhost_line [] {
	assert equal (parse-gateway-ip ($HOSTS | lines | where {|l| not ($l | str contains "gateway.docker.internal")} | str join "\n")) ""
}

def test_gateway_ip_empty [] {
	assert equal (parse-gateway-ip "") ""
}

# A hostname merely containing the name is not the name.
def test_gateway_ip_requires_an_exact_name_match [] {
	assert equal (parse-gateway-ip "10.0.0.1\tnot-gateway.docker.internal.example\n") ""
}

# Equivalence classes the old `hostname -i` parse carried, restated against
# /etc/hosts: ragged whitespace must not shift the fields, and nothing-to-find
# must be "" rather than an error.
def test_gateway_ip_tolerates_ragged_whitespace [] {
	assert equal (parse-gateway-ip "   192.168.65.254 \t gateway.docker.internal   \n") "192.168.65.254"
}

def test_gateway_ip_whitespace_only [] {
	assert equal (parse-gateway-ip "  \n \n") ""
}

# A CR-mangled checkout must not turn the hostname into `…internal\r` and miss.
def test_gateway_ip_survives_crlf [] {
	assert equal (parse-gateway-ip "127.0.0.1\tlocalhost\r\n192.168.65.254\tgateway.docker.internal\r\n") "192.168.65.254"
}

# Docker writes one entry per --add-host; take the first deterministically
# rather than depending on iteration order.
def test_gateway_ip_multiple_entries_takes_the_first [] {
	assert equal (parse-gateway-ip "192.168.65.254\tgateway.docker.internal\n10.0.0.9\tgateway.docker.internal\n") "192.168.65.254"
}

# One address, several names — the compose graph maps host.docker.internal to
# the same host-gateway, so the name may share a line with aliases.
def test_gateway_ip_matches_an_aliased_name [] {
	assert equal (parse-gateway-ip "192.168.65.254\thost.docker.internal gateway.docker.internal\n") "192.168.65.254"
}

def test_loopback_addr [] {
	assert equal (loopback-addr "127.0.0.1") true
	assert equal (loopback-addr "127.0.1.1") true
	assert equal (loopback-addr "::1") true
	assert equal (loopback-addr "172.17.0.1") false
	assert equal (loopback-addr "192.168.65.254") false
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
	test_gateway_ip_is_read_by_name_not_position
	test_gateway_ip_linux_bridge
	test_gateway_ip_never_returns_the_localhost_line
	test_gateway_ip_empty
	test_gateway_ip_requires_an_exact_name_match
	test_gateway_ip_tolerates_ragged_whitespace
	test_gateway_ip_whitespace_only
	test_gateway_ip_survives_crlf
	test_gateway_ip_multiple_entries_takes_the_first
	test_gateway_ip_matches_an_aliased_name
	test_loopback_addr
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
