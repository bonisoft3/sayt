# generate-gomplate.nu — Auto-render *.tmpl files via gomplate + CUE data
export def --wrapped main [...files] {
	glob *.tmpl | each { |t|
		let stem = $t | path parse | get stem
		cue export $"($stem).cue"
			| ^gomplate -d data=stdin:///data.json -f $t -o-
			| save --force=(($env.SAY_GENERATE_ARGS_FORCE? | default "false") == "true") ($stem | path basename)
	} | ignore
}
