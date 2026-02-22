package vscode

#task: {
	label:   string
	type?:   string
	command?: string
	windows?: {
		command?: string
		args?: *[] | string | [ ...string ]
	}
	args?: *[] | string | [ ...string ]
	dependsOn?: [ ...string ]
	problemMatcher?: *[] | [ ...string ]
	group?: {
		kind:      string
		isDefault?: bool
	}
	// allow other VS Code task fields
	...
}

#tasks: {
	version: "2.0.0"
	tasks: [ ...#task ]
}

#gradle: {
	version: #tasks.version
	tasks: [ for t in #tasks.tasks {
		if (t.label == "build") { t & { 
		command: *"./gradlew" | string
		args: *[ "assemble" ] | [ ...string ]
	} }
		if (t.label == "test") { t & { 
		command: "./gradlew" 
		args: *[ "test" ] | [ ...string ]
	} }
	} ]
}
