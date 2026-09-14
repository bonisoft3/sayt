use std/assert
use tools.nu [run-cue]

const source = (path self | path dirname)

def emitted [surface: string]: nothing -> record {
	let expr = $"\(#Loop & {meta: {app: 'fixture'}, surface: {buildCmd: 'echo', testCmd: 'echo', pipelineFiles: [], ($surface)}}\).surface.sayYaml.say" | str replace --all "'" '"'
	run-cue export ($source | path join "loop.cue") -e $expr --out json | from json
}

def main [] {
	let empty = emitted ""
	assert ("generate" not-in ($empty | columns))
	let generated = emitted "verbs: {assets: {verb: 'generate', cmds: ['echo assets'], note: 'assets'}}"
	assert equal $generated.generate.rulemap.assets.cmds [{do: "echo assets"}]
	let checked = emitted "checks: {facts: {verb: 'lint', cmds: ['echo facts'], note: 'facts', priority: 1}}"
	assert equal $checked.lint.rulemap.facts.priority 1
	assert equal $checked.lint.rulemap.facts.cmds [{do: "echo facts"}]
	print "loop_test: all passed"
}
