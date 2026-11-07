#!/usr/bin/env nu
use std/assert

const here = (path self | path dirname)

def plan [project: string, ...args: string] {
    do { ^bash ($here | path join bake-plan.sh) $project .bayt/depot.hcl --print ...$args } | complete
}

def main [] {
    if $nu.os-info.name == "windows" { return }
    let base = (mktemp -d)
    let dir = ($base | path join "project with spaces")
    mkdir $dir
    mkdir ($dir | path join .bayt)
    'include: [included.yaml]' | save ($dir | path join compose.yaml)
    'services:
  leaf:
    image: example.invalid/leaf:ci
    pull_policy: ${BAYT_PULL_POLICY:-build}
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
    'group "depot-build" { targets = ["leaf"] }' | save ($dir | path join .bayt depot.hcl)
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
