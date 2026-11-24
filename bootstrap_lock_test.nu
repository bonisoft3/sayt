#!/usr/bin/env nu
# Regression test: when a bare `sayt` launcher runs in a trusted `locked = true`
# project, it must execute the already-installed full release binary directly
# instead of re-invoking `mise tool-stub sayt-full-<ver>.toml` (which fails
# because `http:sayt-full-<ver>.toml` is absent from the consumer's `mise.lock`).
use std/assert

def main [] {
	if $nu.os-info.name == "windows" {
		print "skipping on windows"
		return
	}

	const root = (path self | path dirname)
	let zig_src = (open --raw ($root | path join "sayt.zig"))
	let mise_ver = ($zig_src | parse --regex 'const MISE_VERSION = "(?P<v>[^"]+)";' | get v.0)
	let mise_path = (which mise | first | get path)

	let tmpdir = (mktemp -d)
	try {
		let bin_dir = ($tmpdir | path join "bin")
		let prefix = ($tmpdir | path join "prefix")
		let home_dir = ($tmpdir | path join "home")
		let xdg_cache = ($tmpdir | path join "xdg-cache")
		let data_dir = ($tmpdir | path join "data")
		let consumer = ($tmpdir | path join "consumer")
		let installed_dir = ($data_dir | path join "installs" "http-sayt-full-v9-9-9-toml" "v9.9.9")

		mkdir $bin_dir $home_dir $xdg_cache $consumer $installed_dir
		for cache_root in [
			($home_dir | path join "Library" "Caches" "sayt" $"mise-($mise_ver)")
			($xdg_cache | path join "sayt" $"mise-($mise_ver)")
		] {
			mkdir $cache_root
			ln -s $mise_path ($cache_root | path join "mise")
		}

		do { cd $root; ^mise exec -- zig build --prefix $prefix }
		cp ($prefix | path join "bin" "sayt") ($bin_dir | path join "sayt")

		"#!/bin/sh\necho \"DIRECT_EXEC=$* MISE_LOCKED=${MISE_LOCKED:-unset}\"\n" | save -f ($installed_dir | path join "sayt")
		chmod +x ($installed_dir | path join "sayt")

		"[settings]\nlocked = true\nlockfile = true\n" | save -f ($consumer | path join ".mise.toml")
		"[tools]\n" | save -f ($consumer | path join "mise.lock")

		let result = (do {
			hide-env -i MISE_LOCKED SAYT_CA_CERT SSL_CERT_FILE
			with-env {
				HOME: $home_dir
				XDG_CACHE_HOME: $xdg_cache
				MISE_DATA_DIR: $data_dir
				MISE_TRUSTED_CONFIG_PATHS: $consumer
				SAYT_VERSION: "v9.9.9"
			} {
				cd $consumer
				^($bin_dir | path join "sayt") hello
			}
		} | complete)

		assert equal $result.exit_code 0 $"sayt exited ($result.exit_code): ($result.stderr)"
		assert ($result.stdout | str contains "DIRECT_EXEC=hello") $"expected direct exec output, got: ($result.stdout)"
		assert ($result.stdout | str contains "MISE_LOCKED=unset") $"expected MISE_LOCKED unset, got: ($result.stdout)"
		print "bootstrap_lock_test: direct exec bypasses consumer lockfile check"
	} catch {|e|
		rm -rf $tmpdir
		error make {msg: $e.msg}
	}
	rm -rf $tmpdir
}
