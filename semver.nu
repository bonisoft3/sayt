#!/usr/bin/env nu
use tools.nu [run-git-cliff]

# Returns { root, rel, prefix } for monorepo tag detection.
# prefix is "" at repo root, "services/tracker/" in a subdirectory.
export def monorepo-context []: nothing -> record {
	let root = (git rev-parse --show-toplevel | str trim)
	let cwd = ($env.PWD | path expand)
	let rel = ($cwd | path relative-to $root)
	let is_sub = ($rel | is-not-empty) and $rel != "."
	{ root: $root, rel: $rel, prefix: (if $is_sub { $"($rel)/" } else { "" }) }
}

# Updates VERSION (if present), creates a release commit, and tags it.
def commit-and-tag [ctx: record, plain_version: string, tag: string] {
	# Update VERSION file if it exists
	if ("VERSION" | path exists) {
		$plain_version | save -f VERSION
		git add VERSION
	}

	# Create commit (--allow-empty for repos without VERSION file)
	git commit --allow-empty -m $"release: ($plain_version)"
	git tag $tag
	print $"Created tag: ($tag)"
	$tag
}

# Determines the next semver tag using git-cliff and conventional commits.
# For monorepo subdirectories, uses prefixed tags (e.g. services/tracker/v0.2.0).
# For repo root, uses plain v* tags.
# Returns the created tag string, or null if no bump is needed.
export def bump-version [
	--dry-run  # Print the tag without creating it
]: nothing -> any {
	let ctx = (monorepo-context)

	let tag_pattern = $"($ctx.prefix)v[0-9].*"
	let existing_tags = (git tag -l $"($ctx.prefix)v*" --sort=-version:refname | lines | where { $in | is-not-empty })

	# First release: no git-cliff needed, use initial version
	if ($existing_tags | is-empty) {
		let tag = $"($ctx.prefix)v0.1.0"
		if $dry_run {
			print $"Would create tag: ($tag)"
			return $tag
		}
		commit-and-tag $ctx "v0.1.0" $tag
		return $tag
	}

	# Subsequent releases: let git-cliff compute the bump with --tag-pattern for scoping
	let cliff_config = if ("cliff.toml" | path exists) {
		"cliff.toml" | path expand
	} else {
		$env.FILE_PWD | path join "cliff.toml"
	}

	let cliff_args = [
		"--config" $cliff_config
		"--repository" $ctx.root
		"--tag-pattern" $tag_pattern
		"--bumped-version"
	]

	let result = do { run-git-cliff ...$cliff_args } | complete
	if $result.exit_code != 0 { return null }
	let version = ($result.stdout | str trim)
	if ($version | is-empty) { return null }

	# git-cliff includes prefix when existing tags have one
	let tag = if ($version | str starts-with $ctx.prefix) {
		$version
	} else {
		$"($ctx.prefix)($version)"
	}

	let plain_version = $tag | str replace $ctx.prefix ""

	# Tag already exists → nothing to bump
	if (git tag -l $tag | str trim | is-not-empty) {
		print $"Tag ($tag) already exists, nothing to bump."
		return null
	}

	if $dry_run {
		print $"Would create tag: ($tag)"
		return $tag
	}

	commit-and-tag $ctx $plain_version $tag
}

# Resolves the current and previous version tags for the monorepo subdirectory.
# Strips the directory prefix so callers get plain semver (e.g. "v0.1.0").
# Returns { current, previous } — previous is omitted when only one tag exists.
# At repo root (no prefix), returns empty.
export def resolve-version-tags []: nothing -> record {
	let ctx = (monorepo-context)
	if ($ctx.prefix | is-empty) { return {} }

	let tags = (git tag -l $"($ctx.prefix)v*" --sort=-version:refname | lines | where { $in | is-not-empty })

	if ($tags | is-empty) { return {} }

	mut result = { current: ($tags | first | str replace $ctx.prefix "") }
	if ($tags | length) > 1 {
		$result = ($result | merge { previous: ($tags | get 1 | str replace $ctx.prefix "") })
	}
	$result
}
