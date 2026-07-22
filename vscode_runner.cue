package vscode

// Parameters provided at evaluation time.
label: *"build" | string @tag(label)
platform: *"linux" | "windows" | "osx" | string @tag(platform)
taskLabel: label

// Schema for the tasks.json content. The actual file gets unified with this.
schema: #tasks
version: schema.version
tasks:  schema.tasks

#selectedTask: [ for t in tasks if t.label == label { t } ][0]

// Resolve a task by label, returning {cmd, args, cwd, env} with the
// host platform's override (vscode-native windows/linux/osx keys).
#resolveTask: {
	_label: string
	_task: [ for t in tasks if t.label == _label { t } ][0]
	_ovr: _task[platform] | {}
	_args: *[] | string | [ ...string ]

	if _task.args != _|_ {
		_args: _task.args
	}

	cmd: _task.command & string
	args: *_args | string | [ ...string ]

	if _task.options != _|_ && _task.options.cwd != _|_ {
		cwd: _task.options.cwd
	}
	if _task.options != _|_ && _task.options.env != _|_ {
		env: _task.options.env
	}

	if _ovr.command != _|_ {
		cmd: _ovr.command
	}
	if _ovr.args != _|_ {
		args: _ovr.args & (string | [ ...string ])
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
