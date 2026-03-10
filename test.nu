# test.nu — Run unit tests via VS Code tasks
use vscode.nu [vtr]

export def --wrapped main [...args] {
	vtr test ...$args
}
