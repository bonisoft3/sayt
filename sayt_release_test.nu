#!/usr/bin/env nu
# Tests for release and semver modules
# Run with: nu sayt_release_test.nu

use std/assert

use semver.nu [compute-version wrap-version validate-version resolve-version-tags]

def main [] {
	print "Running release tests...\n"

	test_release_help_shows_in_main
	test_verify_help_shows_in_main
	test_release_fails_without_goreleaser_config
	test_verify_succeeds_as_nop_without_config
	test_resolve_tags_returns_empty_at_repo_root
	test_resolve_tags_finds_prefixed_tags
	test_resolve_tags_sets_previous_tag
	test_resolve_tags_returns_empty_without_matching_tags
	test_compute_first_release
	test_compute_feat_bumps_minor
	test_compute_fix_bumps_patch
	test_compute_no_conventional_commits_fallback
	test_wrap_version_adds_prefix
	test_wrap_version_adds_v_prefix
	test_validate_version_passes_when_no_file
	test_validate_version_passes_when_matches
	test_validate_version_fails_when_mismatched
	test_release_tags_without_commit
	test_release_dry_run_no_side_effects
	test_release_aborts_on_version_mismatch

	print "\nAll release tests passed!"
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
	assert ($result.current == "v0.2.0") "current should be latest"
	assert ($result.previous == "v0.1.0") "previous should be older"
	rm -rf $tmpdir
}

def test_resolve_tags_returns_empty_without_matching_tags [] {
	print "test resolve-version-tags returns empty when no matching prefixed tags..."
	let tmpdir = (make-test-repo)
	let result = do { cd ($tmpdir | path join "services/tracker"); resolve-version-tags }
	assert ($result | is-empty) "should return empty when no tags"
	rm -rf $tmpdir
}

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

def test_compute_first_release [] {
	print "test compute-version returns v0.1.0 on first release..."
	let tmpdir = (make-bump-repo)
	let result = do { cd ($tmpdir | path join "services/tracker"); compute-version }
	assert ($result.plain_version == "v0.1.0") $"expected v0.1.0, got ($result.plain_version)"
	assert ($result.tag == "services/tracker/v0.1.0") $"expected services/tracker/v0.1.0, got ($result.tag)"
	rm -rf $tmpdir
}

def test_compute_feat_bumps_minor [] {
	print "test compute-version bumps minor on feat commit..."
	let tmpdir = (make-bump-repo)
	git -C $tmpdir tag "services/tracker/v0.1.0"
	"update" | save -f ($tmpdir | path join "services/tracker/file.txt")
	git -C $tmpdir add .
	git -C $tmpdir commit -m "feat: add new feature" -q
	let result = do { cd ($tmpdir | path join "services/tracker"); compute-version }
	assert ($result.plain_version == "v0.2.0") $"expected v0.2.0, got ($result.plain_version)"
	rm -rf $tmpdir
}

def test_compute_fix_bumps_patch [] {
	print "test compute-version bumps patch on fix commit..."
	let tmpdir = (make-bump-repo)
	git -C $tmpdir tag "services/tracker/v0.1.0"
	"fix" | save -f ($tmpdir | path join "services/tracker/file.txt")
	git -C $tmpdir add .
	git -C $tmpdir commit -m "fix: resolve bug" -q
	let result = do { cd ($tmpdir | path join "services/tracker"); compute-version }
	assert ($result.plain_version == "v0.1.1") $"expected v0.1.1, got ($result.plain_version)"
	rm -rf $tmpdir
}

def test_compute_no_conventional_commits_fallback [] {
	print "test compute-version falls back to patch bump..."
	let tmpdir = (make-bump-repo)
	git -C $tmpdir tag "services/tracker/v0.1.0"
	let result = do { cd ($tmpdir | path join "services/tracker"); compute-version }
	assert ($result.plain_version == "v0.1.1") $"expected v0.1.1, got ($result.plain_version)"
	rm -rf $tmpdir
}

def test_wrap_version_adds_prefix [] {
	print "test wrap-version adds monorepo prefix..."
	let tmpdir = (make-bump-repo)
	let result = do { cd ($tmpdir | path join "services/tracker"); wrap-version "v1.0.0" }
	assert ($result.tag == "services/tracker/v1.0.0") $"expected services/tracker/v1.0.0, got ($result.tag)"
	assert ($result.plain_version == "v1.0.0") $"expected v1.0.0, got ($result.plain_version)"
	rm -rf $tmpdir
}

def test_wrap_version_adds_v_prefix [] {
	print "test wrap-version adds v prefix if missing..."
	let tmpdir = (make-bump-repo)
	let result = do { cd ($tmpdir | path join "services/tracker"); wrap-version "1.0.0" }
	assert ($result.plain_version == "v1.0.0") $"expected v1.0.0, got ($result.plain_version)"
	rm -rf $tmpdir
}

def test_validate_version_passes_when_no_file [] {
	print "test validate-version passes when no VERSION file..."
	let tmpdir = (mktemp -d)
	let result = do { cd $tmpdir; validate-version "v1.0.0" }
	assert $result "should pass when no VERSION file"
	rm -rf $tmpdir
}

def test_validate_version_passes_when_matches [] {
	print "test validate-version passes when VERSION matches..."
	let tmpdir = (mktemp -d)
	"v1.0.0" | save ($tmpdir | path join "VERSION")
	let result = do { cd $tmpdir; validate-version "v1.0.0" }
	assert $result "should pass when VERSION matches"
	rm -rf $tmpdir
}

def test_validate_version_fails_when_mismatched [] {
	print "test validate-version fails when VERSION mismatches..."
	let tmpdir = (mktemp -d)
	"v0.9.0" | save ($tmpdir | path join "VERSION")
	let result = do { cd $tmpdir; validate-version "v1.0.0" }
	assert (not $result) "should fail when VERSION mismatches"
	rm -rf $tmpdir
}

def make-release-repo []: nothing -> string {
	let tmpdir = (mktemp -d)
	git -C $tmpdir init -q
	git -C $tmpdir config user.email "test@invalid"
	git -C $tmpdir config user.name "test"
	git -C $tmpdir commit --allow-empty -m "init" -q
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

def test_release_tags_without_commit [] {
	print "test release creates tag without commit..."
	let tmpdir = (make-release-repo)
	let before = (git -C $tmpdir rev-parse HEAD)
	let result = (do { nu sayt.nu -d $tmpdir release } | complete)
	let after = (git -C $tmpdir rev-parse HEAD)
	assert ($before == $after) "HEAD should not move — no commits"
	let tags = (git -C $tmpdir tag -l "v*" | lines | where { $in | is-not-empty })
	assert (not ($tags | is-empty)) "should have created a tag"
	rm -rf $tmpdir
}

def test_release_dry_run_no_side_effects [] {
	print "test release --dry-run creates no tags or commits..."
	let tmpdir = (make-release-repo)
	let before = (git -C $tmpdir rev-parse HEAD)
	let result = (do { nu sayt.nu -d $tmpdir release --dry-run } | complete)
	let after = (git -C $tmpdir rev-parse HEAD)
	assert ($before == $after) "HEAD should not move"
	let tags = (git -C $tmpdir tag -l "v*" | lines | where { $in | is-not-empty })
	assert ($tags | is-empty) "should not have created any tags"
	rm -rf $tmpdir
}

def test_release_aborts_on_version_mismatch [] {
	print "test release aborts when VERSION mismatches..."
	let tmpdir = (make-release-repo)
	"v99.0.0" | save ($tmpdir | path join "VERSION")
	git -C $tmpdir add .
	git -C $tmpdir commit -m "feat: add goreleaser config" -q
	let result = (do { nu sayt.nu -d $tmpdir release } | complete)
	assert ($result.exit_code != 0) "should fail when VERSION mismatches"
	let tags = (git -C $tmpdir tag -l "v*" | lines | where { $in | is-not-empty })
	assert ($tags | is-empty) "should not have created any tags"
	rm -rf $tmpdir
}
