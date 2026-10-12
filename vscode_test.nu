use std/assert

const source = (path self | path dirname)

def main [] {
	let fixture = mktemp -d
	mkdir ($fixture | path join ".vscode")
	{version: "2.0.0", tasks: [{label: "test", type: "shell", command: "echo", args: ["MODULE_PATH_OK"]}]} | to json | save ($fixture | path join ".vscode/tasks.json")
	$'use ($source)/vscode.nu [vtr]
vtr test' | save ($fixture | path join "caller.nu")
	let result = (do {
		cd $fixture
		^nu caller.nu
	} | complete)
	rm -rf $fixture
	assert equal $result.exit_code 0 $result.stderr
	assert ($result.stdout | str contains "MODULE_PATH_OK") $result.stdout
}
