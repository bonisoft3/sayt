# lint-cue.nu — Vet *.cue files against their stem filenames
use tools.nu [run-cue]

export def main [] {
	glob *.cue
		| where { |it| $it | path parse | get stem | path exists }
		| each { |it|
			let stem = $it | path parse | get stem
			let ext = $stem | path parse | get extension | fill -c text
			run-cue vet -c (basename $it) $"($ext):($stem)"
		}
		| ignore
}
