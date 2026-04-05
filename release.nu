# release.nu — Atomic release: compute version, validate, tag, build, deploy
#
# No files are written, no commits are created. VERSION (if present) is a gate:
# if it doesn't match the computed version, release aborts so the user can
# update VERSION and all references, then run lint to verify before retrying.
#
# --version bypasses git-cliff: once tagged, git-cliff picks it up next time.
# --changelog generates release notes via git-cliff and passes them to goreleaser.
use tools.nu [run-goreleaser run-git-cliff]
use semver.nu [compute-version wrap-version validate-version resolve-version-tags monorepo-context]

def tag-on-head []: nothing -> string {
	let ctx = (monorepo-context)
	let pattern = $"($ctx.prefix)v[0-9]*"
	let tags = (git tag -l $pattern --points-at HEAD | lines | where { $in | is-not-empty })
	if ($tags | is-empty) { "" } else { $tags | first }
}

# Generate changelog via git-cliff for unreleased commits
def generate-changelog [ctx: record]: nothing -> string {
	let tag_pattern = $"($ctx.prefix)v[0-9].*"
	let cliff_config = if ("cliff.toml" | path exists) {
		"cliff.toml" | path expand
	} else {
		$env.FILE_PWD | path join "cliff.toml"
	}

	let result = do {
		run-git-cliff --config $cliff_config --repository $ctx.root --tag-pattern $tag_pattern --unreleased --strip header
	} | complete

	if $result.exit_code != 0 or ($result.stdout | str trim | is-empty) {
		return ""
	}
	$result.stdout | str trim
}

export def --wrapped main [
	--snapshot          # Build only, do not deploy
	--dry-run           # Print computed version and exit
	--version: string   # Use explicit version, bypass git-cliff
	--changelog         # Generate release notes via git-cliff
	...args
] {
	if not ((".goreleaser.yaml" | path exists) or (".goreleaser.yml" | path exists)) {
		print -e "No .goreleaser.yaml found. Create one to define your release workflow."
		exit 1
	}

	let ctx = (monorepo-context)
	let head_tag = (tag-on-head)

	# --- Determine current version ---
	mut current_version = ""
	if ($head_tag | is-not-empty) {
		$current_version = ($head_tag | str replace $ctx.prefix "")
		if not $dry_run { print $"Tag ($head_tag) found on HEAD — skipping bump." }
	} else if $snapshot {
		# Snapshot: use current version from tags, skip next-version computation
		let versions = (resolve-version-tags)
		if ($versions.current? | is-not-empty) {
			$current_version = $versions.current
		}
	} else {
		let computed = if ($version | is-not-empty) {
			wrap-version $version
		} else {
			compute-version
		}
		if ($computed | is-empty) {
			print -e "Could not compute version."
			exit 1
		}

		if $dry_run {
			print $"Next version: ($computed.plain_version)"
			return
		}

		# VERSION gate
		if not (validate-version $computed.plain_version) {
			exit 1
		}

		# Tag
		git tag $computed.tag
		print $"Created tag: ($computed.tag)"
		$current_version = $computed.plain_version
	}

	if $dry_run { return }

	# --- Build ---
	let versions = (resolve-version-tags)
	mut goreleaser_env = { BUILDX_BAKE_ENTITLEMENTS_FS: "0" }
	if ($current_version | is-not-empty) {
		$goreleaser_env = ($goreleaser_env | merge { GORELEASER_CURRENT_TAG: $current_version })
	}
	if ($versions.previous? | is-not-empty) {
		$goreleaser_env = ($goreleaser_env | merge { GORELEASER_PREVIOUS_TAG: $versions.previous })
	}

	# Changelog: --changelog generates via git-cliff, passed as --release-notes to goreleaser
	mut release_notes_args = []
	if $changelog {
		let notes = (generate-changelog $ctx)
		if ($notes | is-not-empty) {
			let tmpfile = (mktemp -t release-notes-XXXXXX)
			$notes | save -f $tmpfile
			$release_notes_args = [--release-notes $tmpfile]
		}
	}

	mut goreleaser_args = [--auto-snapshot ...$release_notes_args ...$args]
	if $snapshot and (not ($args | any { $in == "--snapshot" })) {
		$goreleaser_args = [--snapshot ...$goreleaser_args]
	}

	let final_env = $goreleaser_env
	let final_args = $goreleaser_args
	with-env $final_env { run-goreleaser release ...$final_args }
}
