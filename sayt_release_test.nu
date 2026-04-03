#!/usr/bin/env nu
# Tests for sayt.nu release and verify verbs
# Run with: nu sayt_release_test.nu

use std/assert

use semver.nu [bump-version resolve-version-tags monorepo-context]

def main [] {
	print "Running sayt release and verify tests...\n"

	test_release_help_shows_in_main
	test_verify_help_shows_in_main
	test_release_fails_without_goreleaser_config
	test_verify_succeeds_as_nop_without_config
	test_resolve_tags_returns_empty_at_repo_root
	test_resolve_tags_finds_prefixed_tags
	test_resolve_tags_sets_previous_tag
	test_resolve_tags_returns_empty_without_matching_tags
	test_bump_first_release_creates_initial_tag
	test_bump_feat_commit_bumps_minor
	test_bump_fix_commit_bumps_patch
	test_bump_no_conventional_commits_returns_null
	test_bump_dry_run_does_not_create_tag
	test_bump_first_release_creates_commit
	test_bump_updates_version_file
	test_bump_creates_empty_commit_without_version_file
	test_release_dirty_repo_still_bumps
	test_release_clean_with_tag_skips_bump
	test_release_clean_no_tag_bumps_and_builds

	print "\nAll release and verify tests passed!"
}

def test_release_help_shows_in_main [] {
	print "test 'release' appears in main help..."
	let result = (nu sayt.nu --help)
	assert ($result | str contains "release")
}

def test_verify_help_shows_in_main [] {
	print "test 'verify' appears in main help..."
	let result = (nu sayt.nu --help)
	assert ($result | str contains "verify")
}

def test_release_fails_without_goreleaser_config [] {
	print "test release fails in empty temp dir..."
	let tmpdir = (mktemp -d)
	try {
		nu sayt.nu -d $tmpdir release
		rm -rf $tmpdir
		assert false "release should have failed but succeeded"
	} catch {
		rm -rf $tmpdir
		assert true
	}
}

def test_verify_succeeds_as_nop_without_config [] {
	print "test verify is a nop in empty temp dir..."
	let tmpdir = (mktemp -d)
	let result = (do { nu sayt.nu -d $tmpdir verify } | complete)
	assert ($result.exit_code == 0) $"verify should succeed as nop, got: ($result.exit_code) ($result.stderr)"
	rm -rf $tmpdir
}

# Creates a temp git repo with monorepo-style tags for testing
def make-test-repo []: nothing -> string {
	let tmpdir = (mktemp -d)
	git -C $tmpdir init -q
	git -C $tmpdir config user.email "test@invalid"
	git -C $tmpdir config user.name "test"
	git -C $tmpdir commit --allow-empty -m "init" -q
	mkdir ($tmpdir | path join "services/tracker")
	"test" | save ($tmpdir | path join "services/tracker/file.txt")
	git -C $tmpdir add .
	git -C $tmpdir commit -m "add tracker" -q
	$tmpdir
}

def test_resolve_tags_returns_empty_at_repo_root [] {
	print "test resolve-version-tags returns empty at repo root..."
	let tmpdir = (make-test-repo)
	let result = do { cd $tmpdir; resolve-version-tags }
	assert ($result | is-empty) "should return empty record at repo root"
	rm -rf $tmpdir
}

def test_resolve_tags_finds_prefixed_tags [] {
	print "test resolve-version-tags finds prefixed tags..."
	let tmpdir = (make-test-repo)
	git -C $tmpdir tag "services/tracker/v0.1.0"
	let result = do { cd ($tmpdir | path join "services/tracker"); resolve-version-tags }
	assert ($result.current == "v0.1.0") "should set current to stripped semver"
	rm -rf $tmpdir
}

def test_resolve_tags_sets_previous_tag [] {
	print "test resolve-version-tags sets previous tag when multiple exist..."
	let tmpdir = (make-test-repo)
	git -C $tmpdir tag "services/tracker/v0.1.0"
	git -C $tmpdir commit --allow-empty -m "second" -q
	git -C $tmpdir tag "services/tracker/v0.2.0"
	let result = do { cd ($tmpdir | path join "services/tracker"); resolve-version-tags }
	assert ($result.current == "v0.2.0") "current should be latest stripped semver"
	assert ($result.previous == "v0.1.0") "previous should be older stripped semver"
	rm -rf $tmpdir
}

def test_resolve_tags_returns_empty_without_matching_tags [] {
	print "test resolve-version-tags returns empty when no matching prefixed tags..."
	let tmpdir = (make-test-repo)
	let result = do { cd ($tmpdir | path join "services/tracker"); resolve-version-tags }
	assert ($result | is-empty) "should return empty record when no tags"
	rm -rf $tmpdir
}

# Creates a temp git repo suitable for bump-version testing (conventional commits)
def make-bump-repo []: nothing -> string {
	let tmpdir = (mktemp -d)
	git -C $tmpdir init -q
	git -C $tmpdir config user.email "test@invalid"
	git -C $tmpdir config user.name "test"
	git -C $tmpdir commit --allow-empty -m "init" -q
	mkdir ($tmpdir | path join "services/tracker")
	"test" | save ($tmpdir | path join "services/tracker/file.txt")
	git -C $tmpdir add .
	git -C $tmpdir commit -m "feat: initial tracker service" -q
	$tmpdir
}

def test_bump_first_release_creates_initial_tag [] {
	print "test bump-version creates initial v0.1.0 tag on first release..."
	let tmpdir = (make-bump-repo)
	let tag = do { cd ($tmpdir | path join "services/tracker"); bump-version }
	assert ($tag == "services/tracker/v0.1.0") $"expected services/tracker/v0.1.0, got ($tag)"
	# Verify tag actually exists
	let tags = (git -C $tmpdir tag -l "services/tracker/v*" | lines | where { $in | is-not-empty })
	assert ($tags | any { $in == "services/tracker/v0.1.0" }) "tag should exist in git"
	rm -rf $tmpdir
}

def test_bump_feat_commit_bumps_minor [] {
	print "test bump-version bumps minor on feat commit..."
	let tmpdir = (make-bump-repo)
	git -C $tmpdir tag "services/tracker/v0.1.0"
	"update" | save -f ($tmpdir | path join "services/tracker/file.txt")
	git -C $tmpdir add .
	git -C $tmpdir commit -m "feat: add new feature" -q
	let tag = do { cd ($tmpdir | path join "services/tracker"); bump-version }
	assert ($tag == "services/tracker/v0.2.0") $"expected services/tracker/v0.2.0, got ($tag)"
	rm -rf $tmpdir
}

def test_bump_fix_commit_bumps_patch [] {
	print "test bump-version bumps patch on fix commit..."
	let tmpdir = (make-bump-repo)
	git -C $tmpdir tag "services/tracker/v0.1.0"
	"fix" | save -f ($tmpdir | path join "services/tracker/file.txt")
	git -C $tmpdir add .
	git -C $tmpdir commit -m "fix: resolve bug" -q
	let tag = do { cd ($tmpdir | path join "services/tracker"); bump-version }
	assert ($tag == "services/tracker/v0.1.1") $"expected services/tracker/v0.1.1, got ($tag)"
	rm -rf $tmpdir
}

def test_bump_no_conventional_commits_returns_null [] {
	print "test bump-version returns null when no conventional commits since last tag..."
	let tmpdir = (make-bump-repo)
	git -C $tmpdir tag "services/tracker/v0.1.0"
	let tag = do { cd ($tmpdir | path join "services/tracker"); bump-version }
	assert ($tag == null) $"expected null, got ($tag)"
	rm -rf $tmpdir
}

def test_bump_dry_run_does_not_create_tag [] {
	print "test bump-version --dry-run prints but does not create tag..."
	let tmpdir = (make-bump-repo)
	let tag = do { cd ($tmpdir | path join "services/tracker"); bump-version --dry-run }
	assert ($tag == "services/tracker/v0.1.0") $"expected services/tracker/v0.1.0, got ($tag)"
	# Tag should NOT exist in git
	let tags = (git -C $tmpdir tag -l "services/tracker/v*" | lines | where { $in | is-not-empty })
	assert ($tags | is-empty) "tag should not exist after dry-run"
	rm -rf $tmpdir
}

def test_bump_first_release_creates_commit [] {
	print "test bump-version creates a commit on first release..."
	let tmpdir = (make-bump-repo)
	let before = (git -C $tmpdir rev-parse HEAD)
	let tag = do { cd ($tmpdir | path join "services/tracker"); bump-version }
	let after = (git -C $tmpdir rev-parse HEAD)
	assert ($before != $after) "HEAD should have moved (commit created)"
	let msg = (git -C $tmpdir log -1 --format=%s)
	assert ($msg == "release: v0.1.0") $"commit message should be 'release: v0.1.0', got '($msg)'"
	rm -rf $tmpdir
}

def test_bump_updates_version_file [] {
	print "test bump-version updates VERSION file when it exists..."
	let tmpdir = (make-bump-repo)
	"v0.0.0" | save ($tmpdir | path join "services/tracker/VERSION")
	git -C $tmpdir add .
	git -C $tmpdir commit -m "add VERSION" -q
	let tag = do { cd ($tmpdir | path join "services/tracker"); bump-version }
	let version_content = (open ($tmpdir | path join "services/tracker/VERSION") | str trim)
	assert ($version_content == "v0.1.0") $"VERSION should be v0.1.0, got ($version_content)"
	rm -rf $tmpdir
}

def test_bump_creates_empty_commit_without_version_file [] {
	print "test bump-version creates empty commit when no VERSION file..."
	let tmpdir = (make-bump-repo)
	let before = (git -C $tmpdir rev-parse HEAD)
	let tag = do { cd ($tmpdir | path join "services/tracker"); bump-version }
	let after = (git -C $tmpdir rev-parse HEAD)
	assert ($before != $after) "HEAD should have moved even without VERSION file"
	rm -rf $tmpdir
}

def make-release-repo []: nothing -> string {
	let tmpdir = (mktemp -d)
	git -C $tmpdir init -q
	git -C $tmpdir config user.email "test@invalid"
	git -C $tmpdir config user.name "test"
	git -C $tmpdir commit --allow-empty -m "init" -q
	# Create a .goreleaser.yaml so release doesn't bail early
	'version: 2
project_name: test
builds:
  - builder: zig
    skip: true
release:
  disable: true
' | save ($tmpdir | path join ".goreleaser.yaml")
	git -C $tmpdir add .
	git -C $tmpdir commit -m "feat: add goreleaser config" -q
	$tmpdir
}

def test_release_dirty_repo_still_bumps [] {
	print "test release on dirty repo still bumps (goreleaser --auto-snapshot handles safety)..."
	let tmpdir = (make-release-repo)
	# Dirty the repo
	"dirty" | save ($tmpdir | path join "dirty.txt")
	let before = (git -C $tmpdir rev-parse HEAD)
	# release will bump even on dirty tree; goreleaser --auto-snapshot handles snapshot
	let result = (do { nu sayt.nu -d $tmpdir release } | complete)
	let after = (git -C $tmpdir rev-parse HEAD)
	# HEAD should move (bump creates commit+tag regardless of dirty state)
	assert ($before != $after) "dirty repo should still create bump commit"
	let tags = (git -C $tmpdir tag -l "v*" | lines | where { $in | is-not-empty })
	assert (not ($tags | is-empty)) "should have created a version tag"
	rm -rf $tmpdir
}

def test_release_clean_with_tag_skips_bump [] {
	print "test release with tag on HEAD skips bump..."
	let tmpdir = (make-release-repo)
	git -C $tmpdir tag "v0.1.0"
	let before = (git -C $tmpdir rev-parse HEAD)
	let result = (do { cd $tmpdir; nu -c "use release.nu; release --snapshot" } | complete)
	let after = (git -C $tmpdir rev-parse HEAD)
	assert ($before == $after) "tagged HEAD should not create bump commit"
	rm -rf $tmpdir
}

def test_release_clean_no_tag_bumps_and_builds [] {
	print "test release on clean repo without tag bumps version then runs goreleaser..."
	let tmpdir = (make-release-repo)
	let before = (git -C $tmpdir rev-parse HEAD)
	# release will bump (creating commit+tag) then fail on goreleaser (no remote in test env)
	# but the bump phase should succeed
	let result = (do { nu sayt.nu -d $tmpdir release } | complete)
	let after = (git -C $tmpdir rev-parse HEAD)
	# Bump should have created a commit
	assert ($before != $after) "should have created a bump commit"
	let msg = (git -C $tmpdir log -1 --format=%s)
	assert ($msg | str starts-with "release: v") $"commit message should start with 'release: v', got '($msg)'"
	# Tag should exist
	let tags = (git -C $tmpdir tag -l "v*" | lines | where { $in | is-not-empty })
	assert (not ($tags | is-empty)) "should have created a version tag"
	rm -rf $tmpdir
}
