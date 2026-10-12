use config.nu [load-config]
use rulemap.nu [run-rules]

export def main [verb: string] {
	if not (".bayt/checks.yaml" | path exists) { error make {msg: "missing .bayt/checks.yaml; regenerate the Bayt graph"} }
	if $verb == "generate" or $verb != ($env.SAYT_TASK_VERB? | default "") { hide-env -i SAYT_PLATFORM }
	let args = if $verb == ($env.SAYT_TASK_VERB? | default "") {
		$env.SAYT_TASK_ARGS? | default '[]' | from json
	} else { [] }
	with-env {SAYT_CONFIG: .bayt/checks.yaml} {
		mut config = (load-config --config .bayt/checks.yaml)
		if $verb != "generate" { run-rules $config $verb ...$args; return }
		for _ in 1..3 {
			let before = (open --raw .bayt/checks.yaml)
			run-rules $config $verb ...$args
			if (open --raw .bayt/checks.yaml) == $before { return }
			let refreshed = (load-config --config .bayt/checks.yaml)
			if $refreshed.say.generate == $config.say.generate { return }
			$config = $refreshed
		}
		error make {msg: "generation rules did not settle after three executions"}
	}
}
