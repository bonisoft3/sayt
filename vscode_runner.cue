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

// Resolve a task by label, returning {cmd, args} with platform overrides.
#resolveTask: {
	_label: string
	_task: [ for t in tasks if t.label == _label { t } ][0]
	_win: _task.windows | {}
	_args: *[] | string | [ ...string ]
	_winArgs: *[] | string | [ ...string ]

	if _task.args != _|_ {
		_args: _task.args
	}
	if _win.args != _|_ {
		_winArgs: _win.args
	}

	cmd: _task.command & string
	args: *_args | string | [ ...string ]

	if platform == "windows" && _win.command != _|_ {
		cmd: _win.command
	}
	if platform == "windows" && _win.args != _|_ {
		args: _winArgs & (string | [ ...string ])
	}
}

// Build the list of dependency commands (one level deep).
#depLabels: *[] | [ ...string ]
if #selectedTask.dependsOn != _|_ {
	#depLabels: #selectedTask.dependsOn
}

deps: [ for dl in #depLabels {
	(#resolveTask & {_label: dl})
}]

command: {
	label: taskLabel
	(#resolveTask & {_label: label})
}
