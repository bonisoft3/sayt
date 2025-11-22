export def auto-gomplate [] {
	glob *.tmpl | each { 
		|t| cue export $"($t | path parse | get stem).cue" | ^gomplate -d data=stdin:///data.json -f $t -o- | save --force=($env.SAY_GENERATE_ARGS_FORCE? | default false) (basename ($t | path parse | get stem)) 
	}
}
