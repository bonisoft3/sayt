# auto-bayt.nu — the auto-bayt generate rule: run bayt's generator for
# the current project. Nop when the project has no bayt.cue.
use tools.nu [run-nu]

const _self_dir = (path self | path dirname)

# A bayt checkout sibling to this distribution (the monorepo layout)
# runs the local generator with local-checkout runtime refs; any other
# layout (mise http-tarball, installed binary) uses the `bayt` CLI from
# PATH (e.g. `mise install github:bonisoft3/bayt`).
export def main [] {
	if not ("bayt.cue" | path exists) { return }
	let sibling = ($_self_dir | path join ".." "bayt" "core" "generate.nu")
	if ($sibling | path exists) {
		run-nu -I $_self_dir -c $"use ($sibling); generate --runtime plugins/bayt"
	} else {
		^bayt generate
	}
}
