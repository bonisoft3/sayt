use std/assert
use tools.nu [run-cue]

const source = (path self | path dirname)

def emitted [surface: string, root: string = "launchCommand: {}"]: nothing -> record {
	let expr = $"\(#Loop & {meta: {app: 'fixture'}, ($root), surface: {buildCmd: 'echo', testCmd: 'echo', pipelineFiles: [], ($surface)}}\).surface.sayYaml.say" | str replace --all "'" '"'
	run-cue export ($source | path join "loop.cue") -e $expr --out json | from json
}

def main [] {
	let empty = emitted ""
	assert equal $empty.lint.rulemap.cue.cmds [{do: "mise exec -- cue vet ./..."}]
	let concrete = emitted "sayYaml: say: lint: rulemap: cue: cmds: [{do: 'mise exec -- cue vet -c ./...'}]"
	assert equal $concrete.lint.rulemap.cue.cmds [{do: "mise exec -- cue vet -c ./..."}]
	assert ("generate" not-in ($empty | columns))
	let generated = emitted "verbs: {assets: {verb: 'generate', cmds: ['echo assets'], note: 'assets'}}"
	assert equal $generated.generate.rulemap.assets.cmds [{do: "echo assets"}]
	let checked = emitted "checks: {facts: {verb: 'lint', cmds: ['echo facts'], note: 'facts', priority: 1}}"
	assert equal $checked.lint.rulemap.facts.priority 1
	assert equal $checked.lint.rulemap.facts.cmds [{do: "echo facts"}]
	let custom = emitted "verbs: {prepare: {verb: 'launch', cmds: ['echo prepare'], note: 'prepare'}}" "launchCommand: {do: 'dev-launch', use: ''}"
	assert equal $custom.launch.rulemap.builtin.cmds [{do: "echo prepare"}, {do: "dev-launch", use: ""}]
	print "loop_test: all passed"
}
