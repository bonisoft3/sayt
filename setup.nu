# setup.nu — Install runtimes and tools
use tools.nu [run-mise]

export def --wrapped main [...args] {
	run-mise install ...$args
}
