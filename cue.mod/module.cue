// Mirror-only module declaration. Copybara stages this file from
// plugins/sayt/.mirror/cue.mod/ to the bonisoft3/sayt root as
// cue.mod/module.cue. The monorepo itself has no cue.mod here —
// in-monorepo CUE imports resolve against the root cue.mod
// (bonisoft.org).
module: "github.com/bonisoft3/sayt@v0"

language: {
	version: "v0.16.1"
}

source: {
	kind: "git"
}
