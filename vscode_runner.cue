package vscode

// Parameters provided at evaluation time.
label: *"build" | string @tag(label)
platform: *"posix" | "windows" | string @tag(platform)
taskLabel: label

// Schema for the tasks.json content. The actual file gets unified with this.
schema: #tasks
version: schema.version
tasks:  schema.tasks

#selectedTask: [ for t in tasks if t.label == label { t } ][0]
#selectedArgs: *[] | string | [ ...string ]
#windowsArgs:  *[] | string | [ ...string ]
#windows:      #selectedTask.windows | {}

if #selectedTask.args != _|_ {
	#selectedArgs: #selectedTask.args
}
if #windows.args != _|_ {
	#windowsArgs: #windows.args
}

command: {
	label: taskLabel
	cmd:   #selectedTask.command & string
	args:  *#selectedArgs | string | [ ...string ]

	// Prefer platform-specific overrides when present.
	if platform == "windows" && #windows.command != _|_ {
		cmd: #windows.command
	}
	if platform == "windows" && #windows.args != _|_ {
		args: #windowsArgs & (string | [ ...string ])
	}
}
