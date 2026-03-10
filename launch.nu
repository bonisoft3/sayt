# launch.nu — Develop environment launcher
use compose.nu [compose-vrun]

export def --wrapped main [...args] {
	compose-vrun develop ...$args
}
