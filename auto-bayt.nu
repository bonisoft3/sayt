# auto-bayt.nu — the auto-bayt generate rule: run bayt's generator for
# the current project. Nop when the project has no bayt.cue.
use tools.nu [run-nu, compose-stub, mise-bin]

const _self_dir = (path self | path dirname)

# The docker CLI resolves `docker compose` from $DOCKER_CONFIG/cli-plugins
# ahead of the host dirs, so the shim pins the plugin without touching the
# real config. It lives under sayt's cache dir: tmp dirs leak one copy per
# run and CI often mounts them noexec. docker execs the shim from whatever
# project dir the flatten cds into, so the shim must trust that cwd's mise
# config itself (see mise-trust in tools.nu). bayt's only docker use during
# generate is the daemon-less depot flatten (`compose config`), so auth and
# contexts aren't needed.
def pinned-compose-docker-config []: nothing -> string {
	let cache = if ((uname | get kernel-name) == "Darwin") {
		$env.HOME | path join "Library" "Caches" "sayt"
	} else {
		$env.XDG_CACHE_HOME? | default ($env.HOME | path join ".cache") | path join "sayt"
	}
	let cfg = ($cache | path join "docker-config")
	let plugins = ($cfg | path join "cli-plugins")
	mkdir $plugins
	let shim = ($plugins | path join "docker-compose")
	let mise = (mise-bin)
	$"#!/bin/sh\n'($mise)' trust -y -a -q\nMISE_LOCKED=0 exec '($mise)' tool-stub '(compose-stub)' \"$@\"\n" | save -f $shim
	^chmod +x $shim
	$cfg
}

# Windows cli-plugins must be .exe — a shell shim cannot be loaded, so
# resolution stays host-side there. compose.toml does pin a windows binary;
# using it would mean placing the resolved .exe here, not a shim.
# Plain export, not a `main` subcommand — `--wrapped main` swallows every
# arg, so a subcommand spelling would never dispatch.
export def docker-env []: nothing -> record {
	if $nu.os-info.name == "windows" { return {} }
	{ DOCKER_CONFIG: (pinned-compose-docker-config) }
}

# A bayt checkout sibling to this distribution (the monorepo layout)
# runs the local generator with local-checkout runtime refs; any other
# layout (mise http-tarball, installed binary) uses the `bayt` CLI from
# PATH (e.g. `mise install github:bonisoft3/bayt`).
export def --wrapped main [...files] {
	if not ("bayt.cue" | path exists) { return }
	let sibling = ($_self_dir | path join ".." "bayt" "core" "generate.nu")
	with-env (docker-env) {
		if ($sibling | path exists) {
			run-nu -I $_self_dir -c $"use ($sibling); generate --runtime plugins/bayt"
		} else {
			^bayt generate
		}
	}
}
