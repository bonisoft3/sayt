use tools.nu [run-mise run-mise-live verbosity]
use auto-bayt.nu

# go-task's own children print past sayt's helpers, so quiet logs the whole run.
def --wrapped run-task [...args] {
	if (verbosity) != "quiet" {
		run-mise exec -- task ...$args
	} else {
		let code = (run-mise-live exec -- task ...$args)
		if $code != 0 { exit $code }
	}
}

export def --wrapped main [target: string, --generate, ...args] {
	let files = if ("bayt.json" | path exists) { open bayt.json | get -o files | default {} | columns | each { |f| $".bayt/($f)" } } else { [] }
	let tasks = [".bayt/Taskfile.yml" ".bayt/Taskfile.bayt.yml" $".bayt/Taskfile.($target).yaml"] | append (if $generate { [".bayt/Taskfile.generate.yaml"] } else { [] })
	if ($files | append $tasks | any { |f| not ($f | path exists) }) { auto-bayt }
	if $generate and $target != "generate" {
		with-env {SAYT_TASK_ARGS: "[]", BAYT_INVOCATION: "{}"} {
			run-task -t .bayt/Taskfile.yml bayt:generate
		}
	}
	let arguments = ($args | each { into string })
	let invocation = {manifest: ($".bayt/bayt.($target).json" | path expand), value: {args: $arguments, platform: ($env.SAYT_PLATFORM? | default "")}}
	with-env {SAYT_TASK_VERB: ($target | str replace -r "-action$" ""), SAYT_TASK_ARGS: ($arguments | to json --raw), BAYT_INVOCATION: ($invocation | to json --raw)} {
		run-task -t .bayt/Taskfile.yml $"bayt:($target)"
	}
}
