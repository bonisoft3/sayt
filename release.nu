# release.nu — Artifact release with phased pipeline
use tools.nu [run-goreleaser run-git-cliff]
use semver.nu [bump-version resolve-version-tags monorepo-context]

def tag-on-head []: nothing -> string {
	let ctx = (monorepo-context)
	let pattern = $"($ctx.prefix)v[0-9]*"
	let tags = (git tag -l $pattern --points-at HEAD | lines | where { $in | is-not-empty })
	if ($tags | is-empty) { "" } else { $tags | first }
}

# Check if the goreleaser config has changelog.skip set (meaning: use git-cliff instead)
def goreleaser-changelog-skipped []: nothing -> bool {
	let file = if (".goreleaser.yaml" | path exists) { ".goreleaser.yaml" } else { ".goreleaser.yml" }
	let config = open $file
	($config | get -o changelog.skip | default false) or ($config | get -o changelog.disable | default false)
}

# Generate changelog via git-cliff (only when goreleaser changelog is skipped)
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
	--no-bump    # Skip automatic version bump (use existing tags)
	--snapshot   # Build only, do not publish
	--tag: string  # Use explicit version, skip git-cliff computation
	...args
] {
	if not ((".goreleaser.yaml" | path exists) or (".goreleaser.yml" | path exists)) {
		print -e "No .goreleaser.yaml found. Create one to define your release workflow."
		exit 1
	}

	let ctx = (monorepo-context)
	let has_tag_env = ($env.GORELEASER_CURRENT_TAG? | default "" | is-not-empty)
	let head_tag = (tag-on-head)

	# Phase 1: Bump (conditional)
	mut current_version = ""
	if $has_tag_env {
		$current_version = $env.GORELEASER_CURRENT_TAG
	} else if ($tag | is-not-empty) {
		$current_version = $tag
	} else if ($head_tag | is-not-empty) {
		$current_version = ($head_tag | str replace $ctx.prefix "")
		print $"Tag ($head_tag) found on HEAD — skipping bump."
	} else if (not $snapshot) and (not $no_bump) {
		let new_tag = (bump-version)
		if ($new_tag | is-empty) {
			print "No release needed — no conventional commits found since last tag."
			print "Ensure commit messages use conventional format (feat:, fix:, etc.)."
			return
		}
		$current_version = ($new_tag | str replace $ctx.prefix "")
	}

	# Resolve previous version for goreleaser
	mut goreleaser_env = { BUILDX_BAKE_ENTITLEMENTS_FS: "0" }
	if ($current_version | is-not-empty) and (not $has_tag_env) {
		$goreleaser_env = ($goreleaser_env | merge { GORELEASER_CURRENT_TAG: $current_version })
	}
	if (not $has_tag_env) {
		let versions = (resolve-version-tags)
		if ($versions.previous? | is-not-empty) {
			$goreleaser_env = ($goreleaser_env | merge { GORELEASER_PREVIOUS_TAG: $versions.previous })
		}
	}

	# Phase 2: Changelog via git-cliff
	# Only generate when goreleaser config has changelog.skip: true (opt-in to git-cliff).
	# --skip=changelog in args suppresses git-cliff even if opted in.
	let skip_changelog = ($args | any { $in == "--skip=changelog" })
	mut release_notes_args = []
	if (not $skip_changelog) and (goreleaser-changelog-skipped) {
		let changelog = (generate-changelog $ctx)
		if ($changelog | is-not-empty) {
			let tmpfile = (mktemp -t release-notes-XXXXXX)
			$changelog | save -f $tmpfile
			$release_notes_args = [--release-notes $tmpfile]
		}
	}

	# Phase 2+3: Build (and push if not snapshot)
	# --auto-snapshot: goreleaser snapshots automatically on dirty/untagged trees
	mut goreleaser_args = [--auto-snapshot ...$release_notes_args ...$args]
	if $snapshot and (not ($args | any { $in == "--snapshot" })) {
		$goreleaser_args = [--snapshot ...$goreleaser_args]
	}

	# Rebind to immutable for closure capture
	let final_env = $goreleaser_env
	let final_args = $goreleaser_args
	with-env $final_env { run-goreleaser release ...$final_args }
}
