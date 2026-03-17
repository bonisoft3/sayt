#!/usr/bin/env nu
use tools.nu [run-git-cliff]

# Returns { root, rel, prefix } for monorepo tag detection.
# prefix is "" at repo root, "services/tracker/" in a subdirectory.
def monorepo-context []: nothing -> record {
	let root = (git rev-parse --show-toplevel | str trim)
	let cwd = ($env.PWD | path expand)
	let rel = ($cwd | path relative-to $root)
	let is_sub = ($rel | is-not-empty) and $rel != "."
	{ root: $root, rel: $rel, prefix: (if $is_sub { $"($rel)/" } else { "" }) }
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
		git tag $tag
		print $"Created tag: ($tag)"
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

	# Extract plain version (without prefix) for VERSION file check
	let plain_version = $tag | str replace $ctx.prefix ""

	# Tag already exists → nothing to bump
	if (git tag -l $tag | str trim | is-not-empty) {
		print $"Tag ($tag) already exists, nothing to bump."
		return null
	}

	# Check VERSION file matches computed version (only when VERSION exists)
	if ("VERSION" | path exists) {
		let file_version = open VERSION | str trim
		if $file_version != $plain_version {
			print -e $"VERSION file says ($file_version) but git-cliff computed ($plain_version)."
			print -e $"Update VERSION and all version copies to ($plain_version) before releasing."
			exit 1
		}
	}

	if $dry_run {
		print $"Would create tag: ($tag)"
		return $tag
	}

	git tag $tag
	print $"Created tag: ($tag)"
	$tag
}

# Resolves the current and previous version tags for the monorepo subdirectory.
# Strips the directory prefix so callers get plain semver (e.g. "v0.1.0").
# Returns { current, previous } — previous is omitted when only one tag exists.
# At repo root (no prefix), returns empty.
export def resolve-version-tags []: nothing -> record {
	let ctx = (monorepo-context)
	if ($ctx.prefix | is-empty) { return {} }

	let tags = (git tag -l $"($ctx.prefix)v*" --sort=-version:refname | lines | where { $in | is-not-empty })

	if ($tags | is-empty) {
		error make { msg: $"No tag found matching '($ctx.prefix)v*'. Create one with: git tag ($ctx.prefix)v0.1.0" }
	}

	mut result = { current: ($tags | first | str replace $ctx.prefix "") }
	if ($tags | length) > 1 {
		$result = ($result | merge { previous: ($tags | get 1 | str replace $ctx.prefix "") })
	}
	$result
}

# Creates temporary local git tags (without prefix) so tools that need plain semver can find them.
# Accepts a { current, previous } record from resolve-version-tags.
# Returns the list of temporary tag names created.
export def create-temp-tags [versions: record]: nothing -> list<string> {
	let prefix = (monorepo-context).prefix
	mut temp_tags = []
	for key in [current previous] {
		let tag = ($versions | get -o $key | default "")
		if ($tag | is-not-empty) and (git tag -l $tag | str trim | is-empty) {
			let prefixed = $"($prefix)($tag)"
			let commit = (git rev-list -n 1 $prefixed)
			git tag $tag $commit
			$temp_tags = ($temp_tags | append $tag)
		}
	}
	$temp_tags
}

# Removes temporary local git tags
export def cleanup-temp-tags [tags: list<string>] {
	for tag in $tags {
		git tag -d $tag out+err>| ignore
	}
}
