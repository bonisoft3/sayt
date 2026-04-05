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

# Computes the next semver version using git-cliff and conventional commits.
# Returns { tag, plain_version } or null if no version can be determined.
export def compute-version []: nothing -> any {
	let ctx = (monorepo-context)

	let tag_pattern = $"($ctx.prefix)v[0-9].*"
	let existing_tags = (git tag -l $"($ctx.prefix)v*" --sort=-version:refname | lines | where { $in | is-not-empty })

	# First release: use initial version
	if ($existing_tags | is-empty) {
		let tag = $"($ctx.prefix)v0.1.0"
		return { tag: $tag, plain_version: "v0.1.0" }
	}

	# Let git-cliff compute the bump
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
	mut version = ($result.stdout | str trim)

	# Strip prefix if git-cliff included it
	if ($version | str starts-with $ctx.prefix) {
		$version = ($version | str replace $ctx.prefix "")
	}

	# No conventional commits or same as latest → fall back to patch bump
	let latest = ($existing_tags | first | str replace $ctx.prefix "")
	if ($version | is-empty) or ($version == $latest) {
		let stripped = ($latest | str replace "v" "")
		let parts = ($stripped | split row ".")
		$version = $"v(($parts | get 0)).(($parts | get 1)).((($parts | get 2 | into int) + 1))"
		print $"No conventional commits found — patch bump to ($version)"
	}

	let tag = $"($ctx.prefix)($version)"
	{ tag: $tag, plain_version: $version }
}

# Wraps a plain version string into { tag, plain_version } with monorepo prefix.
export def wrap-version [plain_version: string]: nothing -> record {
	let ctx = (monorepo-context)
	mut v = $plain_version
	if not ($v | str starts-with "v") { $v = $"v($v)" }
	{ tag: $"($ctx.prefix)($v)", plain_version: $v }
}

# VERSION gate: if VERSION file exists, it must match the computed version.
# Returns true if ok (no file, or matches). Prints error and returns false if mismatched.
export def validate-version [plain_version: string]: nothing -> bool {
	if not ("VERSION" | path exists) { return true }
	let current = (open VERSION | str trim)
	if $current == $plain_version { return true }
	print -e $"VERSION says ($current) but next version is ($plain_version)."
	print -e $"Update VERSION to ($plain_version) and let the linter sync references first."
	false
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
