# launch.nu — Launch environment.
#
# Usage:
#   sayt launch            one-shot: compose run (clean slate + rebuild)
#   sayt launch --watch    long-running: compose up --watch for file sync
use compose.nu [compose-vrun compose-vup]
use tools.nu [run-docker-compose]

export def --wrapped main [
	--watch    # long-running mode with file sync
	...args
] {
	if $watch {
		run-docker-compose down -v --timeout 0 --remove-orphans launch
		compose-vup launch --build --watch ...$args
	} else {
		compose-vrun launch ...$args
	}
}
