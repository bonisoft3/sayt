# build.nu — Compile code via VS Code tasks
use vscode.nu [vtr]

export def --wrapped main [...args] {
	vtr build ...$args
}
