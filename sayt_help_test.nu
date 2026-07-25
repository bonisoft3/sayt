#!/usr/bin/env nu
# Focused tests for sayt.nu help output
# Run with: nu sayt_help_test.nu

use std/assert

def main [] {
    print "Running sayt help tests...\n"

    test_main_help_shows_doctor_description
    test_help_command_outputs_doctor_help
    test_doctor_flag_help
    test_double_dash_passthrough
    test_integrate_flag_help_shows_flags
    test_help_command_integrate_shows_flags

    print "\nAll help tests passed!"
}

def test_main_help_shows_doctor_description [] {
    print "test main help includes doctor description..."
    let result = (nu sayt.nu --help)
    assert ($result | str contains "sayt.nu doctor")
    assert ($result | str contains "Runs environment diagnostics for required tooling")
}

# doctor has no engine flags, so `help doctor` uniformly renders doctor.nu's
# own `main` help (terse but correct) — the wrapper is never special-cased.
def test_help_command_outputs_doctor_help [] {
    print "test 'sayt help doctor' shows doctor engine help..."
    let result = (nu sayt.nu help doctor)
    assert ($result | str contains "Environment diagnostics") $"expected doctor engine help, got: ($result)"
    assert ($result | str contains "doctor")
}

def test_doctor_flag_help [] {
    print "test 'sayt doctor --help' shows doctor engine help..."
    let result = (nu sayt.nu doctor --help)
    assert ($result | str contains "Environment diagnostics") $"expected doctor engine help, got: ($result)"
    assert ($result | str contains "doctor")
}

def test_double_dash_passthrough [] {
    print "test double-dash passthrough..."
    # Use --help after -- to verify passthrough doesn't break command parsing
    let result = (nu sayt.nu doctor --help -- --noop-flag)
    assert ($result | str contains "doctor")
}

# integrate is dispatched through a thin `main integrate [...args]` wrapper in
# sayt.nu whose auto-help would only show `...args`, hiding the real per-flag
# help declared on integrate.nu's `main`. `--help` must render the engine
# module's flags (--bake, --no-up, ...), not the wrapper's `...args`.
def test_integrate_flag_help_shows_flags [] {
    print "test 'sayt integrate --help' shows per-flag help..."
    let result = (nu sayt.nu integrate --help)
    assert ($result | str contains "--bake") $"expected --bake in integrate help, got: ($result)"
    assert ($result | str contains "--no-up") $"expected --no-up in integrate help, got: ($result)"
    assert ($result | str contains "--depot") $"expected --depot in integrate help, got: ($result)"
    assert ($result | str contains "--with-buildx") $"expected --with-buildx in integrate help, got: ($result)"
    # Must NOT be the bare wrapper help whose only parameter is `...args`.
    assert ($result | str contains "Flags:") $"expected a Flags: section, got: ($result)"
}

def test_help_command_integrate_shows_flags [] {
    print "test 'sayt help integrate' shows per-flag help..."
    let result = (nu sayt.nu help integrate)
    assert ($result | str contains "--bake") $"expected --bake in integrate help, got: ($result)"
    assert ($result | str contains "--no-up") $"expected --no-up in integrate help, got: ($result)"
}

