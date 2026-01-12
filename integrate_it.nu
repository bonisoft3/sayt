#!/usr/bin/env nu
# Integration tests for sayt integrate command
# Run with: nu integrate_test.nu
# Requires: Docker

use std/assert

# Pinned alpine image for reproducible builds
const alpine_image = "alpine@sha256:5405e8f36ce1878720f71217d664aa3dea32e5e5df11acbf07fc78ef5661465b"

def main [] {
    print "Running sayt integrate tests...\n"

    $env.TEST_DIR = setup_test_environment

    try {
        test_success_cleans_up
        test_failure_leaves_containers
        test_clean_slate_removes_leftovers
        test_no_cache_flag_triggers_fresh_build
        test_rmi_local_does_not_clear_build_cache
        test_passthrough_args_work
        print "\nAll integrate tests passed!"
    } catch { |err|
        cleanup_test_environment
        error make { msg: $"Test failed: ($err.msg)" }
    }

    cleanup_test_environment
}

def setup_test_environment [] {
    print "Setting up test environment..."
    let dir = $"($nu.temp-path)/sayt-integrate-test-(random uuid)"
    mkdir $dir
    $dir
}

def cleanup_test_environment [] {
    print "Cleaning up test environment..."
    cd $env.TEST_DIR
    # Ensure any leftover containers are removed
    do -i { ^docker compose down -v --timeout 0 --remove-orphans }
    cd $nu.temp-path
    rm -rf $env.TEST_DIR
}

def create_success_compose [] {
    # Create a compose.yaml that will succeed
    $"services:
  app:
    build:
      context: .
      dockerfile_inline: |
        FROM ($alpine_image)
        CMD [\"sh\", \"-c\", \"while true; do sleep 1; done\"]
    healthcheck:
      test: [\"CMD\", \"true\"]
      interval: 1s
      timeout: 1s
      retries: 1
      start_period: 1s

  integrate:
    build:
      context: .
      dockerfile_inline: |
        FROM ($alpine_image)
        CMD [\"sh\", \"-c\", \"echo 'Test passed!' && exit 0\"]
    depends_on:
      app:
        condition: service_healthy
" | save -f $"($env.TEST_DIR)/compose.yaml"
}

def create_failure_compose [] {
    # Create a compose.yaml that will fail
    $"services:
  app:
    build:
      context: .
      dockerfile_inline: |
        FROM ($alpine_image)
        CMD [\"sh\", \"-c\", \"while true; do sleep 1; done\"]
    healthcheck:
      test: [\"CMD\", \"true\"]
      interval: 1s
      timeout: 1s
      retries: 1
      start_period: 1s

  integrate:
    build:
      context: .
      dockerfile_inline: |
        FROM ($alpine_image)
        CMD [\"sh\", \"-c\", \"echo 'Test failed!' && exit 1\"]
    depends_on:
      app:
        condition: service_healthy
" | save -f $"($env.TEST_DIR)/compose.yaml"
}

def get_container_count []: nothing -> int {
    cd $env.TEST_DIR
    let result = (docker compose ps -a --format json | complete)
    if $result.exit_code != 0 {
        return 0
    }
    let output = $result.stdout | str trim
    if ($output | is-empty) {
        return 0
    }
    # Count non-empty lines (each line is a JSON object for a container)
    $output | lines | where { |line| not ($line | is-empty) } | length
}

def test_success_cleans_up [] {
    print "  test: success case cleans up containers..."

    create_success_compose
    cd $env.TEST_DIR

    # Run integrate (should succeed and cleanup)
    let result = (docker compose up integrate --exit-code-from integrate --build --force-recreate | complete)

    # Verify it succeeded
    if $result.exit_code != 0 {
        # Cleanup and fail
        docker compose down -v --timeout 0 --remove-orphans
        error make { msg: $"Expected success but got exit code ($result.exit_code)" }
    }

    # Now simulate what sayt integrate does on success - cleanup
    docker compose down -v --timeout 0 --remove-orphans

    # Verify no containers remain
    let count = (get_container_count)
    assert ($count == 0) $"Expected 0 containers after success cleanup, got ($count)"

    print "    PASS"
}

def test_failure_leaves_containers [] {
    print "  test: failure case leaves containers for inspection..."

    create_failure_compose
    cd $env.TEST_DIR

    # Ensure clean state first (like sayt integrate does)
    docker compose down -v --timeout 0 --remove-orphans

    # Run integrate (should fail)
    let result = (docker compose up integrate --exit-code-from integrate --build --force-recreate | complete)

    # Verify it failed
    assert ($result.exit_code != 0) "Expected failure but got success"

    # On failure, sayt integrate does NOT cleanup - verify containers exist
    let count = (get_container_count)
    assert ($count > 0) $"Expected containers to remain after failure, got ($count)"

    # Cleanup for next test
    docker compose down -v --timeout 0 --remove-orphans

    print "    PASS"
}

def test_clean_slate_removes_leftovers [] {
    print "  test: clean slate removes leftover containers..."

    create_failure_compose
    cd $env.TEST_DIR

    # First, create leftover containers by running a failure
    let result = (docker compose up integrate --exit-code-from integrate --build --force-recreate | complete)

    # Verify we have leftover containers
    let before_count = (get_container_count)
    assert ($before_count > 0) "Expected leftover containers from failed run"

    # Now simulate what sayt integrate does at start - clean slate
    docker compose down -v --timeout 0 --remove-orphans

    # Verify all containers are removed
    let after_count = (get_container_count)
    assert ($after_count == 0) $"Expected 0 containers after clean slate, got ($after_count)"

    print "    PASS"
}

def create_timestamp_compose [] {
    # Create a compose.yaml that captures build timestamp
    # This helps verify --no-cache actually rebuilds
    # Note: using literal $ in RUN command via string concatenation
    let date_cmd = '$(date +%s%N)'
    $"services:
  app:
    build:
      context: .
      dockerfile_inline: |
        FROM ($alpine_image)
        CMD [\"sh\", \"-c\", \"while true; do sleep 1; done\"]
    healthcheck:
      test: [\"CMD\", \"true\"]
      interval: 1s
      timeout: 1s
      retries: 1
      start_period: 1s

  integrate:
    build:
      context: .
      dockerfile_inline: |
        FROM ($alpine_image)
        RUN echo build-timestamp-($date_cmd) > /build-time.txt
        CMD [\"cat\", \"/build-time.txt\"]
    depends_on:
      app:
        condition: service_healthy
" | save -f $"($env.TEST_DIR)/compose.yaml"
}

def test_no_cache_flag_triggers_fresh_build [] {
    # This test verifies that 'docker compose build --no-cache' actually clears build cache.
    # sayt integrate --no-cache uses this to ensure fresh builds.
    print "  test: --no-cache flag triggers fresh build..."

    create_timestamp_compose
    cd $env.TEST_DIR

    # First build (with cache) - use --quiet to suppress build output
    docker compose build --quiet integrate | complete
    let first_result = (docker compose run --rm integrate | complete)
    let first_timestamp = $first_result.stdout | str trim

    # Second build without --no-cache (should use cache, same timestamp)
    docker compose build --quiet integrate | complete
    let cached_result = (docker compose run --rm integrate | complete)
    let cached_timestamp = $cached_result.stdout | str trim

    # Verify cache was used (timestamps should match)
    assert ($first_timestamp == $cached_timestamp) $"Expected cached build to have same timestamp, got ($first_timestamp) vs ($cached_timestamp)"

    # Third build with --no-cache (should rebuild, different timestamp)
    sleep 100ms  # Ensure time has passed
    docker compose build --quiet --no-cache integrate | complete
    let nocache_result = (docker compose run --rm integrate | complete)
    let nocache_timestamp = $nocache_result.stdout | str trim

    # Verify --no-cache triggered rebuild (timestamps should differ)
    assert ($first_timestamp != $nocache_timestamp) $"Expected --no-cache to produce different timestamp, got ($first_timestamp) vs ($nocache_timestamp)"

    # Cleanup
    docker compose down -v --timeout 0 --remove-orphans

    print "    PASS"
}

def extract_timestamp [output: string] {
    # Extract the build-timestamp line from potentially noisy output
    $output | lines | where { |line| $line =~ "^build-timestamp-" } | first
}

def test_rmi_local_does_not_clear_build_cache [] {
    # This test documents that '--rmi local' removes images but NOT the build cache.
    # This is why sayt integrate --no-cache must use 'docker compose build --no-cache'
    # rather than relying on '--rmi local' alone.
    print "  test: --rmi local does not clear build cache..."

    create_timestamp_compose
    cd $env.TEST_DIR

    # First build - use --quiet to suppress build output, build all services
    docker compose build --quiet | complete
    let first_result = (docker compose run --rm integrate | complete)
    let first_timestamp = extract_timestamp $first_result.stdout

    # Remove images with --rmi local
    docker compose down -v --timeout 0 --remove-orphans --rmi local

    # Rebuild - should use cached layers despite image being removed
    sleep 100ms  # Ensure time has passed
    docker compose build --quiet | complete
    let rebuilt_result = (docker compose run --rm integrate | complete)
    let rebuilt_timestamp = extract_timestamp $rebuilt_result.stdout

    # Verify build cache was still used (timestamps should match)
    # This proves --rmi local alone is insufficient for true no-cache builds
    assert ($first_timestamp == $rebuilt_timestamp) $"Expected --rmi local to preserve build cache, got ($first_timestamp) vs ($rebuilt_timestamp)"

    # Cleanup
    docker compose down -v --timeout 0 --remove-orphans

    print "    PASS"
}

def test_passthrough_args_work [] {
    print "  test: passthrough args work (--quiet-pull)..."

    create_success_compose
    cd $env.TEST_DIR

    # Run with --quiet-pull passthrough arg - should not error
    let result = (docker compose up integrate --exit-code-from integrate --build --force-recreate --quiet-pull | complete)

    # Verify command succeeded (--quiet-pull was accepted)
    if $result.exit_code != 0 {
        docker compose down -v --timeout 0 --remove-orphans
        error make { msg: $"Expected success with --quiet-pull, got exit code ($result.exit_code)" }
    }

    # Cleanup
    docker compose down -v --timeout 0 --remove-orphans

    print "    PASS"
}
