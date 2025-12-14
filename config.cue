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

	// Sort by priority (stable via name), then strip 'priority' field
	out: [
		for i in list.Sort(_flat, {x: {}, y: {}, less: (x.priority < y.priority) || (x.priority == y.priority && x.name < y.name)}) {
			{ for k, v in i if k != "priority" { (k): v } }
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

say: {
	generate: {
		#rule: {
			data?: _
			cmds: [ #nucmd, ...#nucmd ]
			...
		}
		#gomplate: #rule & {
			cmds: [ { 
				use: "./gomplate.nu"
			  do: "gomplate auto-gomplate | ignore" 
			} ]
		}
		#cue: #rule & { 
			cmds: [ { 
					do: "glob *.cue | where { |it| $it | path parse | get stem | path exists } | each { |it| cue export $it --out ($it | path parse | get stem | path parse | get extension | fill -c text) | if ($it | path parse | get extension | is-empty) { $in | str substring 0..-1 } else { $in } | save --force=($env.SAY_GENERATE_ARGS_FORCE? | default false) ($it | path parse | get stem) } | ignore"
	    } ]
		}
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
		#cue: #rule & { 
			cmds: [ { 
				use: "tools.nu"
				do: "glob *.cue | where { |it| $it | path parse | get stem | path exists } | each { |it| tools run-cue vet -c (basename $it) ($it | path parse | get stem | path parse | get extension | fill -c text): ($it | path parse | get stem) } | ignore"
	    } ]
		}
		#rulemap: *(#MapAsList & { "auto-cue": *#cue|null }) | #MapAsList
		rulemap: *null | #MapAsList
		rules: (#MapToList & { "in": rulemap & #rulemap }).out
	}
}
