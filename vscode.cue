package vscode

#task: {
	label:   string
	type?:   string
	command?: string
	#osArm: {
		command?: string
		args?: *[] | string | [ ...string ]
	}
	windows?: #osArm
	linux?:   #osArm
	osx?:     #osArm
	args?: *[] | string | [ ...string ]
	options?: {
		cwd?: string
		env?: {[string]: string}
		...
	}
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
