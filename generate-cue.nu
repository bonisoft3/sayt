# generate-cue.nu — Auto-export *.cue files to their stem filenames
export def main [] {
	glob *.cue
		| where { |it| $it | path parse | get stem | path exists }
		| each { |it|
			let stem = $it | path parse | get stem
			let ext = $stem | path parse | get extension | fill -c text
			let content = cue export $it --out $ext
			let content = if ($stem | path parse | get extension | is-empty) {
				$content | str substring 0..-1
			} else {
				$content
			}
			$content | save --force=($env.SAY_GENERATE_ARGS_FORCE? | default false) $stem
		}
		| ignore
}
