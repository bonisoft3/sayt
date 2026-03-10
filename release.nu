# release.nu — Artifact release
use tools.nu [run-goreleaser]
use semver.nu [bump-version resolve-version-tags create-temp-tags cleanup-temp-tags]

export def --wrapped main [
	--no-bump  # Skip automatic version bump (use existing tags)
	...args
] {
	if not ((".goreleaser.yaml" | path exists) or (".goreleaser.yml" | path exists)) {
		print -e "No .goreleaser.yaml found. Create one to define your release workflow."
		exit 1
	}

	# Auto-bump unless --no-bump or GORELEASER_CURRENT_TAG already set
	if (not $no_bump) and ($env.GORELEASER_CURRENT_TAG? | default "" | is-empty) {
		let dry = ($args | any { $in == "--dry-run" or $in == "--skip=publish" })
		let tag = (bump-version --dry-run=$dry)
		if ($tag | is-empty) {
			print "No release needed (no conventional commits to bump)."
			return
		}
	}

	# Resolve monorepo version tags and map to goreleaser env vars
	let versions = if ($env.GORELEASER_CURRENT_TAG? | default "" | is-not-empty) {
		{}
	} else {
		resolve-version-tags
	}
	mut goreleaser_env = {}
	if ($versions.current? | is-not-empty) { $goreleaser_env = ($goreleaser_env | merge { GORELEASER_CURRENT_TAG: $versions.current }) }
	if ($versions.previous? | is-not-empty) { $goreleaser_env = ($goreleaser_env | merge { GORELEASER_PREVIOUS_TAG: $versions.previous }) }

	let temp_tags = (create-temp-tags $versions)
	try {
		with-env ({ BUILDX_BAKE_ENTITLEMENTS_FS: "0" } | merge $goreleaser_env) { run-goreleaser release --clean ...$args }
	} catch { |e|
		cleanup-temp-tags $temp_tags
		error make { msg: $e.msg }
	}
	cleanup-temp-tags $temp_tags
}
