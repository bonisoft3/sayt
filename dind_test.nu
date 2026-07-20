use std/assert
use dind.nu [parse-host-ip]
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

def main [] {
	test_bridge_single_ip
	test_hostnet_single_ip
	test_multi_homed_trailing_space
	test_single_ip_trailing_space
	test_empty
	test_whitespace_only
	test_is_secret_key
	print "dind_test: all passed"
}
