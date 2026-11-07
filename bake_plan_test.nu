#!/usr/bin/env nu
use std/assert

const here = (path self | path dirname)

def plan [project: string, ...args: string] {
    do { ^$nu.current-exe ($here | path join compose.nu) bake $project bake.hcl --print ...$args } | complete
}

def test_compose_failure_never_starts_bake [] {
    let dir = (mktemp -d)
    let script = ($dir | path join fake.nu)
    'def --wrapped main [...args] {
        if $args.0 == "trust" { return }
        if ($args.1 | path basename) == "compose.toml" {
            print "services: {leaf: {build: {context: .}}}"
            exit 42
        }
        touch $env.BAKE_STARTED
    }' | save $script
    let windows = $nu.os-info.name == "windows"
    let exe = ($dir | path join (if $windows { "mise.cmd" } else { "mise" }))
    if $windows {
        $"@echo off\r\n\"($nu.current-exe)\" --no-config-file \"($script)\" %*\r\n" | save $exe
    } else {
        $"#!/bin/sh\nexec '($nu.current-exe)' --no-config-file '($script)' \"$@\"\n" | save $exe
        ^chmod +x $exe
    }
    let marker = ($dir | path join started)
    let result = (with-env {SAYT_MISE_BIN: $exe, BAKE_STARTED: $marker} { plan $dir depot-build })
    assert ($result.exit_code != 0)
    assert equal ($result.stdout | str trim) ""
    assert (not ($marker | path exists)) "Compose failure must stop before Bake starts"
    rm -rf $dir
}

def main [] {
    test_compose_failure_never_starts_bake
    let base = (mktemp -d)
    let dir = ($base | path join "project with spaces")
    mkdir $dir
    'include: [included.yaml]' | save ($dir | path join compose.yaml)
    'services:
  leaf:
    image: example.invalid/leaf:ci
    pull_policy: ${PULL_POLICY:-build}
    build:
      context: .
      dockerfile_inline: FROM scratch
      args:
        LITERAL: $$HOME
      x-bake:
        platforms: [linux/amd64]
        cache-from: ["type=registry,ref=example.invalid/cache"]
        output: [type=docker]
' | save ($dir | path join included.yaml)
    'group "depot-build" { targets = ["leaf"] }' | save ($dir | path join bake.hcl)
    let result = (plan $dir depot-build)
    assert equal $result.exit_code 0 $result.stderr
    let evaluated = ($result.stdout | from json)
    assert equal $evaluated.target.leaf.tags ["example.invalid/leaf:ci"]
    assert equal $evaluated.target.leaf.args.LITERAL '$HOME'
    assert equal $evaluated.target.leaf.platforms [linux/amd64]
    assert equal $evaluated.target.leaf.cache-from.0.ref example.invalid/cache
    assert equal $evaluated.target.leaf.output.0.type docker
    let missing = (plan $dir no-such-target)
    assert ($missing.exit_code != 0)
    assert equal ($missing.stdout | str trim) ""
    let included = ($dir | path join included.yaml)
    open --raw $included | str replace '    image:' '    env_file: absent-runtime.env
    image:' | save -f $included
    let runtime_file = (plan $dir depot-build)
    assert ($runtime_file.exit_code != 0)
    assert ($runtime_file.stderr | str contains absent-runtime.env)
    'services: [' | save -f ($dir | path join compose.yaml)
    let malformed = (plan $dir depot-build)
    assert ($malformed.exit_code != 0)
    assert equal ($malformed.stdout | str trim) ""
    rm -rf $base

    print "All build plan tests passed!"
}
