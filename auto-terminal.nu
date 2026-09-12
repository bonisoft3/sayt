# auto-terminal.nu — the auto-terminal generate rule: state which omnishell
# this project's emitted commands name. Nop when the project has no program.cue.

const _self_dir = (path self | path dirname)

# An omnishell checkout sibling to this distribution (the monorepo layout)
# has the project name that checkout's launcher by a path; any other layout
# (mise http-tarball, installed binary) names the `omnishell` CLI on PATH
# (e.g. `mise install github:bonisoft3/omnishell`). Windows cannot load the
# POSIX launcher, so the sibling is probed and run through its PowerShell twin
# there.
#
# The stanza is the terminal's to write — this rule states the layout and
# where the answer goes, and knows nothing else about the program it generates
# for.
export def --wrapped main [...files] {
	if not ("program.cue" | path exists) { return }
	let windows = $nu.os-info.name == "windows"
	let entry = if $windows { "omnishell.ps1" } else { "omnishell" }
	let sibling = ($_self_dir | path join ".." "omnishell" "runtime" $entry)
	let stanza = if ($sibling | path exists) {
		if $windows {
			^pwsh -NoProfile -File $sibling mode . --local
		} else {
			^$sibling mode . --local
		}
	} else {
		^omnishell mode .
	}
	$"($stanza)\n" | save -f "program_terminal.cue"
}
