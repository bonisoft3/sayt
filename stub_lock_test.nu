#!/usr/bin/env nu
# A consumer in locked mode resolves a stub only from the lock above it, keyed
# by the stub's basename, and `mise lock` keeps only the stubs the lock lists:
# a stub added or renamed without `mise generate tool-stub --lock` would fail
# at a consumer's first run, nu.toml first of all.
use std assert

def main [] {
	const root = (path self | path dirname)
	let lock = (open --raw ($root | path join "mise.lock") | from toml)
	let stubs = (glob ($root | path join "*.toml") | where {|f| (open --raw $f) =~ '(?m)^\[platforms\.' })
	assert ($stubs | is-not-empty) "no stubs found"
	for stub in $stubs {
		let name = ($stub | path basename)
		assert ($"http:($name)" in ($lock.tools | columns)) $"($name) has no entry in plugins/sayt/mise.lock; run `mise generate tool-stub --lock ($name)`"
		assert ($name in $lock.tool-stubs) $"($name) is not listed in mise.lock's tool-stubs; `mise lock` would drop its entry"
	}
	print $"stub_lock_test: ($stubs | length) stubs are locked beside .mise.toml"
}
