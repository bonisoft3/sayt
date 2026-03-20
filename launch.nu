# launch.nu — Launch environment
use compose.nu [compose-vrun]

export def --wrapped main [...args] {
	compose-vrun launch ...$args
}
