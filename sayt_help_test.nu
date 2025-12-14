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

    print "\nAll help tests passed!"
}

def test_main_help_shows_doctor_description [] {
    print "test main help includes doctor description..."
    let result = (nu sayt.nu --help)
    assert ($result | str contains "sayt.nu doctor")
    assert ($result | str contains "Runs environment diagnostics for required tooling")
}

def test_help_command_outputs_doctor_help [] {
    print "test 'sayt help doctor' shows description..."
    let result = (nu sayt.nu help doctor)
    assert ($result | str contains "Runs environment diagnostics for required tooling")
    assert ($result | str contains "doctor")
}

def test_doctor_flag_help [] {
    print "test 'sayt doctor --help' shows description..."
    let result = (nu sayt.nu doctor --help)
    assert ($result | str contains "Runs environment diagnostics for required tooling")
    assert ($result | str contains "--help")
}

def test_double_dash_passthrough [] {
    print "test double-dash passthrough..."
    let result = (nu sayt.nu doctor -- -- --noop-flag)
    assert ($result | str contains "pkg")
}
