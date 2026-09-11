# compose.nu — Docker Compose orchestration helpers
use tools.nu [run-mise-live, compose-stub]
use dind.nu

# --session: an open dind bridge whose ABI (+ the HOST_ENV projection graphs
# env-source as the host.env secret) rides the compose env. The caller owns
# open/close, so one bridge can span several compose invocations.
# Returns the exit code run-live-style instead of raising, so callers can
# close the bridge and print a verdict on failure.
export def --wrapped compose-vrun [--session: any = null, ...args] {
	let base = { COMPOSE_BAKE: "true", BUILDX_NO_DEFAULT_ATTESTATIONS: "1", MISE_LOCKED: "0" }
	let envs = if $session == null { $base } else {
		$base | merge $session.env | insert HOST_ENV (dind to-env-file $session.env)
	}
	run-mise-live --envs $envs tool-stub (compose-stub) ...$args
}

export def --wrapped compose-vup [--session: any = null, target, ...args] {
	compose-vrun --session=$session up $target ...$args
}

# nu dispatches `main <subcommand>` only when a bare `main` is also defined.
def main [] { }

def "main compose-project" [] { compose-project }
# The compose project name this directory's invocations resolve to. sayt does
# not set it: a project publishes it through `[env] COMPOSE_PROJECT_NAME` in
# its `.mise.toml`, resolved through this, so an activated shell and every
# process it starts — sayt included — read one value. A name only sayt could
# compute would leave a bare `docker compose ps` addressing another checkout's
# stack, which is the condition this answers, so the answer stays a report.
#
# Callable from inside a mise `[env]` template: nushell is reached through
# `mise tool-stub`, which applies no `[env]` of its own — measured across
# mise 2026.3.5, 2026.3.17 and 2026.5.2, for a literal value and for an
# `exec()` template alike — so resolving this cannot re-enter env resolution.
# Reaching nushell through `mise exec` instead would close that cycle.
export def compose-project []: nothing -> string {
	# The caller's own choice is the answer whenever it exists: this reports the
	# name compose will use, not the name it would otherwise be given. It is
	# checked first because the two git calls below cost a subprocess each on
	# what a mise `[env]` template makes the shell's directory-change path.
	let override = ($env.COMPOSE_PROJECT_NAME? | default "" | str trim)
	if ($override | is-not-empty) { return $override }
	let base = (compose-slug (project-dir | path basename))
	let raw_worktree = (worktree-name)
	let worktree = (compose-slug $raw_worktree)
	# A worktree whose name normalizes away would drop its prefix and rejoin the
	# main checkout's stack, which is the one case this exists to prevent.
	if ($raw_worktree | is-not-empty) and ($worktree | is-empty) {
		error make {msg: $"worktree '($raw_worktree)' has no characters a compose project name can keep"}
	}
	# Always prefixed in a worktree, even where that repeats a name — `rove-rove`
	# at a worktree root. Skipping the prefix when the halves match would give a
	# worktree named after an app the main checkout's name for that app.
	let name = if ($worktree | is-empty) { $base } else { $"($worktree)-($base)" }
	# compose reads an empty COMPOSE_PROJECT_NAME as unset and reaches for its own
	# default, and refuses one that starts with a dash, so a name that normalizes
	# to nothing must say so here rather than at every later invocation.
	if ($name | is-empty) or ($base | is-empty) {
		error make {msg: $"no compose project name for (project-dir): its basename normalizes to nothing"}
	}
	$name
}

# compose's project directory: the nearest ancestor holding a compose file,
# because compose searches upward when the working directory has none. Falling
# back to the working directory matches compose's own last resort.
export def project-dir []: nothing -> string {
	let names = ["compose.yaml" "compose.yml" "docker-compose.yaml" "docker-compose.yml"]
	mut dir = ($env.PWD | path expand)
	loop {
		if ($names | any { |n| ($dir | path join $n) | path exists }) { return $dir }
		let parent = ($dir | path dirname)
		if $parent == $dir { break }
		$dir = $parent
	}
	$env.PWD | path expand
}

# Empty in a plain checkout. Compose derives its default project from a
# directory basename, and every checkout of a repository has the same
# basenames, so two worktrees running one app share a project and each
# `down -v` takes the other's containers and volumes. The worktree's name is
# what separates them.
def worktree-name []: nothing -> string {
	if (which git | is-empty) { return "" }
	let git_dir = (^git rev-parse --git-dir | complete)
	let common_dir = (^git rev-parse --git-common-dir | complete)
	if $git_dir.exit_code != 0 or $common_dir.exit_code != 0 { return "" }
	let g = ($git_dir.stdout | str trim | path expand)
	let c = ($common_dir.stdout | str trim | path expand)
	# A worktree's own git dir lives under the common one; a plain checkout's is it.
	if $g == $c { return "" }
	$g | path basename
}

# compose's own normalization: keep lowercase alphanumerics, dashes and
# underscores, drop everything else, and trim until the first of the first two.
# Substituting a dash instead of dropping would name a project compose would
# have called something else, which renames the stack rather than finding it.
export def compose-slug [name: string]: nothing -> string {
	$name | str lowercase | str replace --all --regex '[^a-z0-9_-]' '' | str replace --regex '^[^a-z0-9]+' ''
}
