package say

import "list"

// #MapAsList implements the "Ordered Map" pattern to solve common configuration
// composition challenges with standard YAML lists.
//
// Unlike standard lists, which are often rigid (append-only or replace-all),
// this pattern uses stable keys to allow granular modification:
//   - Append:  Add a new unique key.
//   - Modify:  Reference an existing key to merge/update fields.
//   - Delete:  Set an existing key to null.
//   - Order:   Control output position via the optional 'priority' field.
#MapAsList: {
	#el: { name: string, priority?: int, ... }
	[Name=_]: #el & { name: Name } | null
}

#MapToList: {
	in: { [string]: #MapAsList.#el | null }

	// Flatten, filter nulls, and ensure priority defaults to 0
	_flat: [for v in in if v != null { v & { priority: *0 | int } }]

	// Sort by priority (stable via name), strip 'priority' field,
	// and remove empty-string 'use' from cmds (sentinel for "no module")
	out: [
		for i in list.Sort(_flat, {x: {}, y: {}, less: (x.priority < y.priority) || (x.priority == y.priority && x.name < y.name)}) {
			{ for k, v in i if k != "priority" {
				if (k) != "cmds" { (k): v }
				if (k) == "cmds" {
					cmds: [ for cmd in v {
						{ for ck, cv in cmd if !(ck == "use" && cv == "") { (ck): cv } }
					}]
				}
			} }
		}
	]
}

// Defines the type for an environment variable string. (No change)
#envVarString: string & =~"^[a-zA-Z_][a-zA-Z0-9_]*=.*$"

// #nucmd defines the schema for a portable nushell command execution block.
#nucmd: {
	do: string // the nushell statement to execute within a do { $do } block
	use?: string  // a nushell module to import before running the do block
	// --- common fields ---
	workdir?: string // the directory where the command will be executed.
	label?: string // a short human-readable name for the command/step.
	env?: [...#envVarString] // list of environment variables (name=value).
	args?: [...string] // arguments to pass to the nushell executable itself.
	inputs?: [...string] // list of files or directories the 'do' command depends on.
	outputs?: [...string] // list of files or directories the 'do' command is expected to produce.
}

// #verb defines a configurable verb with three override levels:
//   1. Simple:   say.<verb>.do: "command"
//   2. Advanced: say.<verb>.rulemap: { rule1: {...}, rule2: {...} }
//   3. Script:   .sayt.<verb>.nu or .sayt.nu with "main <verb>"
#verb: {
	// Simple form: a single command replaces the builtin
	do?:  string
	use?: string

	// Internal: effective do/use for the builtin cmd, overridden by shorthand.
	// Each verb entry sets defaults (e.g. _builtinDo: *"true" | _).
	// When the user sets say.<verb>.do, the if-guard feeds it through.
	_builtinDo: string
	if do != _|_ {
		_builtinDo: do
	}
	_builtinUse: string
	if use != _|_ {
		_builtinUse: use
	}

	// Advanced form: ordered map of named rules
	#rulemap: *null | #MapAsList
	rulemap:  *null | #MapAsList

	// Resolved rules: merge user rulemap with defaults, sort by priority
	rules: (#MapToList & {"in": rulemap & #rulemap}).out
}

say: {
	generate: {
		#rule: {
			data?: _
			cmds: [ #nucmd, ...#nucmd ]
			...
		}
		#gomplate: #rule & { cmds: [{ use: "./generate-gomplate.nu", do: "generate-gomplate" }] }
		#cue:      #rule & { cmds: [{ use: "./generate-cue.nu",      do: "generate-cue" }] }
		// Do a bit of gymnastics to allow merging with cue but also hiding the intermediate
		// rulemap. If I use a _rulemap it wont merge with the quoted "_rulemap" in yaml
		#rulemap: *(#MapAsList & { "auto-gomplate": *#gomplate|null, "auto-cue": *#cue|null }) | #MapAsList
		rulemap: *null | #MapAsList
		rules: (#MapToList & { "in": rulemap & #rulemap }).out
	}
	lint: {
		#lintcmd: #nucmd & { outputs: [] }
		#rule: {
			data?: _
			cmds: [ #lintcmd, ...#lintcmd ]
			...
		}
		#cue: #rule & { cmds: [{ use: "./lint-cue.nu", do: "lint-cue" }] }
		#rulemap: *(#MapAsList & { "auto-cue": *#cue|null }) | #MapAsList
		rulemap: *null | #MapAsList
		rules: (#MapToList & { "in": rulemap & #rulemap }).out
	}
	setup:     #verb & { _builtinDo: *"setup" | _,     _builtinUse: *"./setup.nu" | _,     #rulemap: #MapAsList & { "builtin": { stop: true, cmds: [{ do: _builtinDo, use: _builtinUse }] } } }
	doctor:    #verb & { _builtinDo: *"doctor" | _,    _builtinUse: *"./doctor.nu" | _,    #rulemap: #MapAsList & { "builtin": { stop: true, cmds: [{ do: _builtinDo, use: _builtinUse }] } } }
	build:     #verb & { _builtinDo: *"build" | _,     _builtinUse: *"./build.nu" | _,     #rulemap: #MapAsList & { "builtin": { stop: true, cmds: [{ do: _builtinDo, use: _builtinUse }] } } }
	test:      #verb & { _builtinDo: *"test" | _,      _builtinUse: *"./test.nu" | _,      #rulemap: #MapAsList & { "builtin": { stop: true, cmds: [{ do: _builtinDo, use: _builtinUse }] } } }
	launch:    #verb & { _builtinDo: *"launch" | _,    _builtinUse: *"./launch.nu" | _,    #rulemap: #MapAsList & { "builtin": { stop: true, cmds: [{ do: _builtinDo, use: _builtinUse }] } } }
	integrate: #verb & { _builtinDo: *"integrate" | _, _builtinUse: *"./integrate.nu" | _, #rulemap: #MapAsList & { "builtin": { stop: true, cmds: [{ do: _builtinDo, use: _builtinUse }] } } }
	release:   #verb & { _builtinDo: *"release" | _,   _builtinUse: *"./release.nu" | _,   #rulemap: #MapAsList & { "builtin": { stop: true, cmds: [{ do: _builtinDo, use: _builtinUse }] } } }
	verify:    #verb & { _builtinDo: *"verify" | _,    _builtinUse: *"./verify.nu" | _,    #rulemap: #MapAsList & { "builtin": { stop: true, cmds: [{ do: _builtinDo, use: _builtinUse }] } } }
}
