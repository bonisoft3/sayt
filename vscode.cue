package vscode

#tasks: {
	version: "2.0.0"
	tasks: [{
		label:   "build"
		type:    "shell"
		command: string
		windows?: command: string
		args?: [ ...string ]
		problemMatcher: *[] | [ ...string ]
		group: {
			kind:      "build"
			isDefault: true
		}
	}, {
		label:   "test"
		type:    "shell"
		command: string
		windows?: command: string
		args?: [ ...string ]
		group: {
			kind:      "test"
			isDefault: true
		}
		problemMatcher: *[] | [ ...string ]
	}]
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
