# rulemap.nu — the config-rule executor: run say.<verb>'s rules
# exactly as the merged config defines them (platform filter, verb-
# and rule-level args, generate's file semantics).
use tools.nu [run-nu]
use config.nu [load-config "path relpath"]

const _self_dir = (path self | path dirname)

# cmd.use (a path relative to sayt's dir) → absolute module path. Single
# resolver shared by run-rules (execution) and resolve-engine (help).
export def cmd-module [use_rel: string]: nothing -> string {
	$_self_dir | path join $use_rel
}

# A verb whose merged config is a single module-backed rule (the builtin
# `{ use: "./integrate.nu", do: "integrate" }` shape) → { module, command }
# with `module` an absolute engine path; null when the verb has no such rule
# (config-driven `do:` verbs, nops). sayt.nu's `main help` renders the engine
# module's own per-flag help through this; run-rules executes the same module
# via cmd-module, so the resolution lives in exactly one place.
export def resolve-engine [config: record, verb: string]: nothing -> any {
	let rules = $config.say? | default {} | get -o $verb | default {} | get -o rules | default []
	let cmd = $rules
		| where { |r| ($r.cmds? | default [] | length) == 1 }
		| each { |r| $r.cmds | first }
		| where { |c| ($c.use? | is-not-empty) and ($c.do? | is-not-empty) }
		| get -o 0
	if ($cmd == null) { return null }
	let module = (cmd-module $cmd.use)
	if not ($module | path exists) { return null }
	{ module: $module, command: $cmd.do }
}

export def --wrapped run-rules [config: record, verb: string, ...args] {
	let verb_config = $config.say? | default {} | get -o $verb | default {}
	let rules = $verb_config.rules? | default []

	if ($rules | is-empty) {
		return  # No rules = nop
	}

	# Filter rules by platform
	let verb_default_platform = $verb_config.platform? | default "local"
	let resolved_platform = $env.SAYT_PLATFORM? | default $verb_default_platform
	let targeted_rules = $rules | where { |rule|
		let rule_platform = $rule.platform? | default null
		if ($rule_platform == null) {
			# Rules without a platform field match only the verb's default platform
			$resolved_platform == $verb_default_platform
		} else {
			$rule_platform == $resolved_platform
		}
	}

	# If platform was explicitly set and no rules match, error
	if ($targeted_rules | is-empty) and ($resolved_platform != $verb_default_platform) {
		print -e $"Error: no rule for platform '($resolved_platform)' in verb '($verb)'"
		exit 1
	}

	let rules = if ($targeted_rules | is-empty) { $rules } else { $targeted_rules }

	# Args naming declared rule outputs narrow the run to those rules
	# (no rule declares a match → all rules run).
	let rules = if ($args | is-not-empty) {
		let file_set = $args
		let filtered = $rules | where { |rule|
			$rule.cmds | any { |cmd|
				$cmd.outputs? | default [] | any { |output| $output in $file_set }
			}
		}
		if ($filtered | is-empty) { $rules } else { $filtered }
	} else { $rules }

	# generate's args are output selectors: consumed above, never cmd
	# args (user rule dos are closed statements), validated to exist
	# after the rules run.
	let selectors = if $verb == "generate" { $args } else { [] }
	let args = if $verb == "generate" { [] } else { $args }

	for rule in $rules {
		let cmds = $rule.cmds? | default []
		if ($cmds | is-empty) { continue }

		# Verb-level args (`say.<verb>.args`) are all-or-nothing: applied
		# only when the CLI passed nothing. Rule-level `rule.args`
		# always apply (internal wiring).
		let verb_args = if ($args | is-empty) and ($resolved_platform == $verb_default_platform) {
			$verb_config.args? | default "" | str trim
		} else { "" }
		let rule_args = $rule.args? | default "" | str trim
		let merged_parts = [
			$verb_args,
			$rule_args,
			...($args | each { |a| if ($a | str contains ' ') { $a | to nuon } else { $a } })
		] | where { |p| $p != "" }
		let args = $merged_parts | str join " " | split row " " | where { |a| $a != "" }

		if ($cmds | length) == 1 {
			# Single cmd: passthrough args
			let cmd = $cmds | first
			# cmd.use paths resolve against sayt's own dir, not the caller's CWD.
			let use_stmt = if ($cmd.use? | is-empty) { "" } else { $"use (cmd-module $cmd.use);" }
			let args_str = ($args | each { |a| if ($a | str contains ' ') { $a | to nuon } else { $a } } | str join ' ')
			run-nu -I ($_self_dir | path relpath $env.PWD) -c $"($use_stmt) ($cmd.do) ($args_str)"
		} else {
			# Multi cmd: args as env var
			let args_str = ($args | str join ' ')
			for cmd in $cmds {
				let use_stmt = if ($cmd.use? | is-empty) { "" } else { $"use (cmd-module $cmd.use);" }
				with-env { SAYT_VERB_ARGS: $args_str } {
					run-nu -I ($_self_dir | path relpath $env.PWD) -c $"($use_stmt) ($cmd.do)"
				}
			}
		}

		if ($rule.stop? | default false) { break }
	}

	for file in $selectors {
		if (not ($file | path exists)) {
			print -e $"Failed to generate ($file)"
			exit -1
		}
	}
}

# The --script entry always runs the verb's default platform: gate
# tasks are spawned from arbitrary sayt verbs (e.g. verify@preview
# running `task bayt:integrate`) and must not inherit their platform.
export def --wrapped main [verb: string, ...args] {
	hide-env --ignore-errors SAYT_PLATFORM
	run-rules (load-config) $verb ...$args
}
